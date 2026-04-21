# Nex-Gen Corporate Dashboard — Guide

**Audience:** Nex-Gen LED LLC internal staff (Tyler and the corporate team)

The Corporate Dashboard is your cross-dealer command center — every dealer's pipeline, every inventory shortfall, every waste trend, plus the admin controls to shape the network itself. Permanent residential and commercial lighting that works as hard as you do, and this dashboard is how you keep the network that delivers it running at the same standard.

## What you'll need

- The Lumina app on a phone or tablet, signed in as Nex-Gen LED LLC staff
- Your **4-digit Corporate PIN** (separate from dealer and installer PINs)
- A laptop for side work when you're digging into Firestore directly (Owner role only)
- About 15 minutes if you're walking the full tour

This guide covers every tab, every metric, and every admin action.

---

## 1. Getting in

The Corporate Dashboard sits behind a separate **4-digit Corporate PIN** — distinct from dealer and installer PINs.

1. Open the Lumina app
2. Tap the **Lumina logo** 5 times on the login screen to open the Staff PIN screen
3. Enter your 4-digit **Corporate PIN**
4. The PIN is validated against the master corporate config (SHA-256 hash in Firestore)
5. On success, you land on the Corporate Dashboard

### Lockout

- **5 failed attempts** locks the keypad — restart the app to try again
- A shake animation and red error text confirm each failed attempt

### Session timeout

- Your corporate session lasts **60 minutes** of inactivity
- A warning appears **5 minutes before** timeout so you can extend without losing context
- Tap any button or scroll to reset the timer

---

## 2. Corporate roles

Every corporate session has a role that decides what you see and what you can change. Four roles total:

| Role | Read access | Write access |
|---|---|---|
| **Owner** | All tabs, all data | Everything — dealer CRUD, pricing defaults, PIN management, announcements |
| **Officer** | All tabs, all data | Most writes — publish/archive announcements, toggle dealer active status. Cannot change system PINs. |
| **Warehouse** | Network + Pipeline (read-only). Full access to Warehouse intelligence. | Reorder intelligence (read-only insights — actual ordering happens externally) |
| **Read-only** | All tabs (data only) | None — pure observability |

Your role is set on the Corporate PIN record. Contact the Owner if you need a different one. The role you logged in with is shown as a badge in the dashboard header so you always know what you can do.

---

## 3. Dashboard layout

The dashboard is a **4-tab shell**:

1. **Network** — Dealer health overview
2. **Pipeline** — Cross-dealer job pipeline
3. **Warehouse** — Network inventory intelligence
4. **Admin** — Network management controls

The current session (your name and role) sits in the header.

---

## 4. Network tab — dealer health

Your default landing tab and the bird's-eye view of the whole dealer network.

### Header metrics

Across the top, a horizontal scroll of **4 stat cards**:

| Card | Icon | Meaning |
|---|---|---|
| **Active dealers** | Store (cyan) | Dealers currently flagged active |
| **Jobs this month** | Briefcase (violet) | Jobs created this calendar month across every dealer |
| **Revenue this month** | Money (green) | Sum of `totalPriceUsd` across every job this calendar month |
| **Avg job value** | Trending up (gold) | Total revenue this month ÷ total jobs this month |

Health for the entire network, at a glance.

### Dealer cards

Below the metrics, a card per dealer.

Each card shows:

| Element | Meaning |
|---|---|
| **Company name** (top) | Business name (or dealer code if name is missing) |
| **Dealer code** (under name) | 2-digit identifier |
| **Health chip** (top-right) | Color-coded — Active / Quiet / Stalled |
| **"This month" pill** | Jobs created this calendar month |
| **"Active" pill** | Jobs not yet at install complete |
| **"Last job" pill** | Relative time since the dealer's most recent job (*Today*, *3d ago*, *2w ago*, *5mo ago*, or *No jobs yet*) |

Tap any dealer card for the dealer detail screen (currently a stub — full per-dealer detail is on the roadmap).

### Health indicators

Each dealer is automatically classified into one of three states based on recent job activity:

| State | Color | Meaning |
|---|---|---|
| **Active** | Green | Producing jobs recently — healthy and running |
| **Quiet** | Amber | Slowed down — worth a check-in |
| **Stalled** | Red | No jobs in a long time — needs attention |

Thresholds are computed server-side from `lastJobCreatedAt` and recent job counts, so they can be tuned without an app update.

### Role gating

- **Owner / Officer / Read-only / Warehouse** — every role can view the Network tab
- No role can edit data from here directly — drilling into a dealer surfaces the read-only detail screen

---

## 5. Pipeline tab — cross-dealer jobs

The most powerful read-only view in the dashboard — every job from every dealer in one searchable, filterable list. Useful for spotting stalls, auditing dealers, and understanding network-wide flow.

### Stats bar

A horizontal strip of metrics across the top:

| Stat | Meaning |
|---|---|
| **Total jobs** | Every sales job in the system |
| **This week** | Jobs created in the last 7 days |
| **Last 30 days** | Jobs created in the last 30 days |
| **Avg cycle** | Rolling average days from creation to install complete |
| **Total revenue** | Sum of `totalPriceUsd` across all jobs |

### Filtering and searching

Below the stats:

- **Status chips** — toggle chips for every job status (Draft, Estimate Sent, Estimate Signed, Pre-wire Scheduled, Pre-wire Complete, Install Scheduled, Install Complete). Tap **All** to clear, or individual chips to filter.
- **Search bar** — free-text across customer name, address, city, and dealer code (case-insensitive substring match).

### Job cards

Each job displays:

| Element | Meaning |
|---|---|
| **Customer name + total price** | Top row, name left, price right (green) |
| **Address, city** | Single ellipsized line |
| **Status chip** | Color-coded by current status |
| **Dealer chip** | Violet — which dealer owns the job (e.g., *"Dealer 42"*) |
| **Stall indicator** | Optional — appears when a job has been in its current status too long |
| **Date created** | Bottom-right, short format |

### Stall indicators

The dashboard tracks how long each job has been in its current status (`now − updatedAt` in days).

| Days in status | Indicator |
|---|---|
| **< 7 days** | No indicator — moving normally |
| **7–14 days** | Amber chip — *"{N}d in status"* — worth checking |
| **> 14 days** | Red chip — *"Stalled {N}d"* — needs intervention |

Use these to spot dealers whose jobs are getting stuck. A signed job sitting in `estimateSigned` for 20 days means the electrician hasn't picked it up — call the dealer.

### Job detail screen (read-only)

Tap any job card to open the **Corporate Job Detail** screen. Full read-only view:

- **Prospect info** — name, address, city, state, zip, email, phone, status badge, dealer code badge
- **Timeline** — every milestone (created, estimate sent, signed, Day 1 scheduled, Day 1 complete, Day 2 scheduled, Day 2 complete), green dots for hit milestones, gray for upcoming
- **Channel runs** — number, label, linear feet for every channel
- **Estimate breakdown** — every line item (description, qty, unit, retail total) plus material/labor subtotals and margin
- **Install dates** — Day 1 and Day 2 dates and completion timestamps
- **Photos** — install-complete photos from Day 2 wrap-up in a horizontal carousel

A **Read-only** badge in the top-right confirms you can't edit from this view.

---

## 6. Warehouse tab — network inventory intelligence

A unified view of inventory across every dealer, plus aggregate intelligence on demand and waste.

### Network inventory summary

First section — per-material breakdown across the entire network:

- **Per material**: display name, total on-hand across all dealers
- **Expandable** to a per-dealer breakdown — each row shows dealer code, on-hand quantity, reserved quantity, and a low-stock alert if any
- **"LOW" badge** appears at the network level when any dealer for that material is at or below their reorder threshold

Network totals and the specific dealers running low, in one place.

### Active demand view

Pulled from every open job (anything not yet `installComplete`):

- **Per material**: total quantity needed across all open jobs, sorted descending
- **Job count**: how many jobs need that material
- **On-hand inventory**: best-effort match against the network inventory summary
- **Gap**: *on-hand − committed*
  - **Positive (green +X)** — surplus
  - **Negative (red GAP X)** — over-committed; the network doesn't have enough to satisfy current demand

> **Note:** Demand-to-inventory matching uses the first keyword token of the description as a best-effort heuristic. Some materials may not match cleanly until SKU bridging is fully wired.

### Network waste intelligence

Cross-dealer view of the same waste data dealers see in their own inventory dashboard. Which materials waste most across the network, which dealers are best and worst at managing each one.

**Per material:**
- Average waste % across all completed installs (network-wide), sorted worst-first
- **Color coding:**
  - **Red** — waste ≥ 20%
  - **Amber** — waste 10–19%
  - **Green** — waste < 10%
- **Sample count** — completed installs in the dataset
- **Best performer** — dealer with the lowest waste % for this material
- **Worst performer** — dealer with the highest

This is training and dealer-management gold. Use it to:

- Identify dealers who need waste-reduction training
- Spot estimate templates that are systematically inflated
- Recognize and reward the best dealers

### Reorder triggers

Materials where corporate-level intervention may be needed.

**Logic:** a material is flagged if `on-hand < (avg per-job usage × 4)` — fewer than 4 jobs' worth of buffer network-wide.

Each card shows:

- Material description
- On-hand quantity
- Needed quantity (based on demand)
- Shortfall (negative — how short you are)

Cards sorted by shortfall ascending (worst first).

Read-only intelligence — actual ordering happens through your normal supply chain. The dashboard just tells you where to focus.

---

## 7. Admin tab — network management

Where corporate staff manage the network itself — adding dealers, setting pricing, publishing announcements, managing system PINs.

**Role gating:**

- **Owner** — full access to every admin section
- **Officer** — can manage dealers and announcements; cannot change system PINs or pricing defaults
- **Warehouse / Read-only** — no admin access

### Section A — Dealer management

Every dealer in the network, with controls to add, edit, and activate/deactivate.

**Each row shows:**

- Company name (or dealer code)
- Dealer code
- **Active toggle** — flip on/off to enable or disable
- **Edit button** — opens the dealer edit sheet

#### Adding a dealer

1. Tap **Add** at the top of the section
2. The **Dealer Edit Sheet** opens with empty fields:
   - **Business name** (required)
   - **Contact email**
   - **Contact phone**
   - **Territory** (state code, optional)
3. Fill in and tap **Save**
4. The new dealer appears in the list immediately, in active state

#### Editing an existing dealer

1. Tap the **Edit** (pencil) icon on the row
2. The same sheet opens, pre-filled
3. Make changes and tap **Save**

#### Activating / deactivating

1. Flip the **active toggle** on the dealer's row
2. The change saves immediately
3. **Deactivation effects:**
   - Their installers can no longer log in (PIN validation checks `isActive`)
   - Their existing jobs remain in the system
   - Their data still appears in cross-network reports
   - The dealer is effectively frozen

Use deactivation to suspend dealers without losing their history.

### Section B — Network pricing defaults

Network-wide pricing rules. Individual dealers can override these with dealer-specific pricing when needed.

**Three editable fields:**

| Field | Format | What it controls |
|---|---|---|
| **Price per linear foot ($)** | Decimal | Default customer price per foot of LED strip |
| **Labor rate per foot ($)** | Decimal | Default labor cost per foot used in estimate generation |
| **Waste factor** | Decimal (e.g., `0.08` for 8%) | Padding applied to material quantities to account for waste |

**To save:** edit the fields and tap **Save** in the section header. On success, the pricing defaults provider is invalidated and refetched, so dealers immediately pick up the new values.

**Dealer-specific pricing** lives on each dealer's record. The estimate generator first looks for that dealer's pricing — if none is set, it falls back to the network defaults configured here.

### Section C — Network announcements

Publish network-wide messages that appear in dealer dashboards and installer screens.

**The list shows every active announcement,** each row displaying:

- **Title**
- **Audience badge** — who sees it (All, Dealers, Installers, or Sales)
- **Body text**
- **Archive button** to retire the announcement when it's no longer relevant

#### Publishing a new announcement

1. Tap **New** at the top of the section
2. The **Announcement Composer** sheet opens:
   - **Title** (required)
   - **Body** (required, multi-line)
   - **Audience** dropdown — **All**, **Dealers**, **Installers**, or **Sales**
3. Tap **Publish**
4. The announcement appears in the list immediately; the audience sees it the next time they open the app

#### Archiving

1. Tap **Archive** on the row
2. The announcement is marked inactive and disappears from the dealer-facing UI
3. Archived announcements are kept in the system for audit but no longer shown

Use announcements for:

- Network-wide policy changes
- Product updates
- Pricing changes (with effective date)
- Holiday schedules
- System maintenance windows

### Section D — System PINs

Master PINs that control access to each mode of the app. **Owner only.**

**Each slot shows:**

- **Slot label** (e.g., "Corporate PIN", "Installer PIN", "Sales PIN")
- **Set / Not set** status badge
- **Change PIN** button

#### Changing a PIN

1. Tap **Change PIN** on the slot
2. The **Change PIN** sheet opens:
   - **Current PIN** — required if a PIN is already set on this slot (for verification)
   - **New PIN** — exactly 4 digits
   - **Confirm new PIN** — must match
3. Tap **Save**
4. The system verifies the current PIN (if applicable) and sets the new one
5. The list refreshes — the slot shows the new "Set" status

**Important:** PIN changes take effect immediately. Anyone using the old PIN is locked out. Coordinate PIN changes with affected users in advance.

---

## 8. Quick reference

| I want to... | Tab | Section |
|---|---|---|
| See total network revenue this month | Network | Header metrics |
| Find a stalled job across all dealers | Pipeline | Filter by status; look for red stall indicators |
| See which dealer has the most active jobs | Network | Dealer cards (sort by "Active" pill) |
| Look at a specific job in detail | Pipeline | Tap any job card |
| Check who's wasting the most LED strip | Warehouse | Network waste intelligence |
| Spot inventory shortfalls before they hit jobs | Warehouse | Reorder triggers |
| Add a new dealer to the network | Admin | Dealer Management → **Add** |
| Suspend a dealer without deleting them | Admin | Dealer Management → Active toggle |
| Change the network's default pricing | Admin | Pricing Defaults |
| Push a message to all dealers | Admin | Network Announcements → **New** |
| Rotate a master PIN | Admin | System PINs (Owner only) |

---

## What success looks like

- You open the dashboard in the morning and know, within 60 seconds, which dealers need a check-in today
- Red stall indicators on the Pipeline tab stay rare — jobs move through the funnel on pace
- Network waste averages stay in the green (< 10%) for your highest-volume materials
- Reorder triggers give you heads-up on shortfalls before any dealer calls to report it
- Every announcement you publish reaches its intended audience (confirmed by dealer acknowledgments or activity)

## If something isn't working

**"The PIN won't let me in."**
Confirm the Corporate PIN hash in Firestore matches the PIN you're entering. 5 failed attempts locks the keypad — restart the app. If you've lost the PIN entirely, update `pin_hash` in `app_config/master_corporate_pin` with the SHA-256 of a new PIN.

**"Network metrics show stale numbers."**
The dashboard reads from live Firestore, but some aggregations are computed server-side. Pull to refresh the tab. If still stale after a minute, check the related Cloud Function logs for errors.

**"A dealer shows Stalled even though they closed a job this week."**
The health classification uses `lastJobCreatedAt`, not install-complete timestamps. If a dealer only updates existing jobs and doesn't create new ones, they can appear Stalled. This is intentional — it surfaces dealers whose pipeline is drying up.

**"Demand-to-inventory match is missing a material."**
The match uses the first keyword token of the material description. If a material description has unusual phrasing, it won't match cleanly until SKU bridging is fully wired. Flag the description to the engineering team.

**"I changed a PIN and someone's locked out."**
That's expected — PIN changes are immediate. Coordinate rotations in advance, and if you've cut someone off inadvertently, rotate again to a PIN they know.

---

**Need help?** This dashboard is internal-only. Contact the Owner directly for role escalation or system issues.
