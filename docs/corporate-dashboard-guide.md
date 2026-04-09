# Nex-Gen Corporate Dashboard — Guide

**Audience:** Nex-Gen LED LLC internal staff (Tyler and the corporate team)

The Corporate Dashboard is the cross-dealer command center for the Nex-Gen LED network. It gives corporate staff visibility into every dealer's pipeline, inventory, and performance, plus admin controls for managing the network as a whole.

This guide covers every tab, every metric, and every administrative action available in the dashboard.

---

## 1. Accessing the Corporate Dashboard

The Corporate Dashboard is gated behind a separate **4-digit corporate PIN** that's distinct from dealer and installer PINs.

### How to access
1. Open the Lumina app.
2. From the main launch screen, tap **Installer Mode**.
3. From the **Installer Landing** screen, tap the **Corporate (Nex-Gen)** tile (gold outline).
4. The **Corporate PIN** screen opens with a numeric keypad.
5. Enter your 4-digit corporate PIN.
6. The PIN is validated against the Nex-Gen master corporate config.
7. On success, you're taken to the Corporate Dashboard.

### Lockout
- **5 failed attempts** locks the keypad. You'll need to restart the app to try again.
- A shake animation and red error text confirm each failed attempt.

### Session timeout
- The corporate session lasts **60 minutes** of inactivity.
- A warning appears **5 minutes before** timeout so you can extend without losing context.
- Tap any button or scroll to reset the timer.

---

## 2. Corporate Roles

Every corporate session has a role that controls what you can see and do. There are **4 roles**:

| Role | Read access | Write access |
|---|---|---|
| **Owner** | All tabs, all data | All admin actions: dealer CRUD, pricing defaults, PIN management, announcements |
| **Officer** | All tabs, all data | Most writes: publish/archive announcements, toggle dealer active status. Cannot change system PINs. |
| **Warehouse** | Network and Pipeline (read-only). Full access to Warehouse intelligence. | Reorder intelligence (read-only insights — actual ordering happens externally) |
| **Read-only** | All tabs (data only) | None — pure observability |

Your role is set on the corporate PIN record itself. Contact the Owner if you need a different role.

The role you logged in with is shown as a badge in the dashboard header so you always know what you can do.

---

## 3. Dashboard Layout

The dashboard is a **4-tab shell**:

1. **Network** — Dealer health overview
2. **Pipeline** — Cross-dealer job pipeline
3. **Warehouse** — Network inventory intelligence
4. **Admin** — Network management controls

The current session (your name and role) is shown in the header.

---

## 4. Network Tab — Dealer Health Overview

This is the default tab and your bird's-eye view of the entire dealer network.

### Header metrics

Across the top of the Network tab you'll see **4 stat cards** in a horizontal scroll:

| Card | Icon | Meaning |
|---|---|---|
| **Active dealers** | Store (cyan) | Total dealers currently flagged active |
| **Jobs this month** | Briefcase (violet) | Count of all jobs created this calendar month, across every dealer |
| **Revenue this month** | Money (green) | Sum of `totalPriceUsd` across every job created this calendar month |
| **Avg job value** | Trending up (gold) | Total revenue this month divided by total jobs this month |

These give you at-a-glance health for the entire network.

### Dealer cards

Below the metrics is a list of **dealer cards** — one per dealer in the network.

Each card shows:

| Element | Meaning |
|---|---|
| **Company name** (top) | The dealer's business name (or dealer code if name is missing) |
| **Dealer code** (under name) | 2-digit dealer identifier |
| **Health chip** (top-right) | Color-coded — Active / Quiet / Stalled |
| **"This month" pill** | Number of jobs created this calendar month |
| **"Active" pill** | Number of jobs not yet at install complete |
| **"Last job" pill** | Relative time since the dealer's most recent job (e.g., *Today*, *3d ago*, *2w ago*, *5mo ago*, or *No jobs yet*) |

Tap any dealer card to drill into the dealer detail screen (currently a stub — full per-dealer detail is on the roadmap).

### Health indicators — Active / Quiet / Stalled

Each dealer is automatically classified into one of three health states based on their recent job activity:

| State | Color | Meaning |
|---|---|---|
| **Active** | Green | Dealer has produced jobs recently — healthy and running |
| **Quiet** | Amber | Dealer exists but has slowed down — worth a check-in |
| **Stalled** | Red | Dealer has not produced jobs in a long time — needs attention |

The exact thresholds are computed from the dealer's job history (specifically `lastJobCreatedAt` and the count of recent jobs). The classification is generated server-side and can be tuned without an app update.

### Role gating

- **Owner / Officer / Read-only / Warehouse** — all roles can view the Network tab.
- No role can edit data here directly — drilling into a dealer surfaces the read-only detail screen.

---

## 5. Pipeline Tab — Cross-Dealer Job View

The Pipeline tab is the most powerful read-only view in the dashboard. It shows every job from every dealer in one searchable, filterable list — useful for spotting stalls, auditing dealers, and understanding network-wide flow.

### Stats bar

Across the top is a horizontal stats strip:

| Stat | Meaning |
|---|---|
| **Total jobs** | Count of every sales job in the system |
| **This week** | Jobs created in the last 7 days |
| **Last 30 days** | Jobs created in the last 30 days |
| **Avg cycle** | Average days from creation to install complete (rolling) |
| **Total revenue** | Sum of `totalPriceUsd` across all jobs |

### Filtering and searching jobs

Below the stats bar you'll find:

- **Status chips** — A row of toggle chips for every job status: Draft, Estimate Sent, Estimate Signed, Pre-wire Scheduled, Pre-wire Complete, Install Scheduled, Install Complete. Tap **All** to clear, or tap individual chips to filter to those statuses.
- **Search bar** — Free-text search across customer name, address, city, and dealer code (case-insensitive substring match).

### Job cards

Each job appears as a card showing:

| Element | Meaning |
|---|---|
| **Customer name** + **total price** | Top row, name on left, price on right (green) |
| **Address, city** | Single line, ellipsized |
| **Status chip** | Color-coded by current status |
| **Dealer chip** | Violet — shows which dealer owns the job (e.g., *"Dealer 42"*) |
| **Stall indicator** | Optional — appears when the job has been in its current status too long |
| **Date created** | Bottom-right, short format |

### Stall indicators (days in status)

The dashboard tracks how long each job has been in its current status (using the job's `updatedAt` timestamp). This is calculated as `now - updatedAt` in days.

| Days in status | Indicator |
|---|---|
| **< 7 days** | No indicator — job is moving normally |
| **7–14 days** | Amber chip — *"{N}d in status"* — worth checking |
| **> 14 days** | Red chip — *"Stalled {N}d"* — needs intervention |

Use these to spot dealers whose jobs are getting stuck. A signed job that's been in `estimateSigned` for 20 days means the electrician hasn't picked it up — call the dealer.

### Job detail screen (read-only)

Tap any job card to open the **Corporate Job Detail** screen. This is a full read-only view containing:

- **Prospect info** — name, address, city, state, zip, email, phone, status badge, dealer code badge
- **Timeline** — every milestone (created, estimate sent, signed, Day 1 scheduled, Day 1 complete, Day 2 scheduled, Day 2 complete) with green dots for hit milestones and gray dots for upcoming
- **Channel runs** — number, label, linear feet for every channel
- **Estimate breakdown** — every line item (description, qty, unit, retail total) plus material/labor subtotals and margin
- **Install dates** — Day 1 and Day 2 dates and completion timestamps
- **Photos** — install-complete photos from Day 2 wrap-up shown in a horizontal carousel

A **Read-only** badge in the top-right confirms you cannot edit anything from this view.

---

## 6. Warehouse Tab — Network Inventory Intelligence

The Warehouse tab gives you a unified view of inventory across every dealer plus aggregate intelligence on demand and waste.

### Network inventory summary

The first section is a per-material breakdown across the entire network:

- **Per material:** display name, total on-hand across all dealers
- **Expandable** to show the per-dealer breakdown — each row shows dealer code, on-hand quantity, reserved quantity, and a low-stock alert if any
- **"LOW" badge** appears at the network level if any dealer for that material is at or below their reorder threshold

This tells you both network-wide inventory totals and which specific dealers are running low.

### Active demand view

The second section pulls from every open job (anything not yet `installComplete`):

- **Per material:** total quantity needed across all open jobs, sorted descending
- **Job count:** how many jobs need that material
- **On-hand inventory:** best-effort match against the network inventory summary
- **Gap calculation:** *On-hand minus committed*
  - **Positive (green +X)** — surplus
  - **Negative (red GAP X)** — over-committed; the network does not have enough of this material to satisfy current demand

> **Note:** Demand-to-inventory matching uses the first keyword token of the description as a best-effort heuristic. Some materials may not match cleanly until SKU bridging is fully wired.

### Network waste intelligence

The third section is the cross-dealer view of the same waste data dealers see in their own inventory dashboard. It tells you which materials waste most across the network and which dealers are best vs. worst at managing each one.

**Per material:**
- Average waste % across all completed installs (network-wide), sorted worst-first
- **Color coding:**
  - **Red** — waste ≥ 20%
  - **Amber** — waste 10–19%
  - **Green** — waste < 10%
- **Sample count** — how many completed installs are in the dataset
- **Best performer** — the dealer with the lowest waste % for this material
- **Worst performer** — the dealer with the highest waste %

This is a **training and dealer-management gold mine.** Use it to:
- Identify dealers who need waste-reduction training
- Spot estimate templates that are systematically inflated
- Recognize and reward the best dealers

### Reorder triggers

The fourth section flags materials where corporate-level intervention may be needed.

**Logic:** A material is flagged if `on-hand < (avg per-job usage × 4)` — i.e., the network has fewer than 4 jobs' worth of buffer.

**Each card shows:**
- Material description
- On-hand quantity
- Needed quantity (based on demand)
- Shortfall (negative number — how short you are)

Cards are sorted by shortfall ascending (worst first).

This is a read-only intelligence section — actual ordering happens through your normal supply chain processes. The dashboard just tells you where to focus.

---

## 7. Admin Tab — Network Management

The Admin tab is where corporate staff manage the network itself — adding dealers, setting pricing, publishing announcements, and managing system PINs.

**Role gating:**
- **Owner** — full access to all admin sections
- **Officer** — can manage dealers and announcements; cannot change system PINs or pricing defaults
- **Warehouse / Read-only** — no admin access

### Section A: Dealer Management

Lists every dealer in the network with controls to add, edit, and activate/deactivate them.

**Each row shows:**
- Company name (or dealer code)
- Dealer code
- **Active toggle** — flip on/off to enable or disable the dealer
- **Edit button** — opens the dealer edit sheet

#### Adding a new dealer
1. Tap the **Add** button at the top of the section.
2. The **Dealer Edit Sheet** opens with empty fields:
   - **Business name** (required)
   - **Contact email**
   - **Contact phone**
   - **Territory** (state code, optional)
3. Fill in the form and tap **Save**.
4. The new dealer appears in the list immediately.
5. The dealer is created in active state by default.

#### Editing an existing dealer
1. Tap the **Edit** button (pencil icon) on the dealer's row.
2. The same sheet opens, pre-filled with the dealer's current info.
3. Make changes and tap **Save**.

#### Activating / deactivating a dealer
1. Flip the **active toggle** on the dealer's row.
2. The change saves immediately.
3. **When you deactivate a dealer:**
   - Their installers can no longer log in (PIN validation checks `isActive`)
   - Their existing jobs remain in the system
   - Their data still appears in cross-network reports
   - They are effectively frozen

Use this to suspend dealers without deleting their history.

### Section B: Network Pricing Defaults

Sets the network-wide default pricing rules. Individual dealers can override these with dealer-specific pricing if they need different numbers.

**Three editable fields:**

| Field | Format | What it controls |
|---|---|---|
| **Price per linear foot ($)** | Decimal | Default customer price per foot of LED strip |
| **Labor rate per foot ($)** | Decimal | Default labor cost per foot used in estimate generation |
| **Waste factor** | Decimal (e.g., `0.08` for 8%) | Padding applied to material quantities to account for waste |

**To save:** edit the fields and tap **Save** (the action is in the section header). On success, the pricing defaults provider is invalidated and refetched so dealers immediately pick up the new values.

**Dealer-specific pricing** lives on each dealer's record. When the salesperson generates an estimate, the system first looks for that dealer's pricing — if none is set, it falls back to the network defaults configured here.

### Section C: Network Announcements

Publish network-wide messages that appear in dealer dashboards and installer screens.

**The list shows every active announcement,** with each row displaying:
- **Title**
- **Audience badge** — who sees this announcement (All, Dealers, Installers, or Sales)
- **Body text**
- **Archive button** to retire the announcement when it's no longer relevant

#### Publishing a new announcement
1. Tap **New** at the top of the section.
2. The **Announcement Composer** sheet opens:
   - **Title** (required)
   - **Body** (required, multi-line)
   - **Audience** dropdown — pick **All**, **Dealers**, **Installers**, or **Sales**
3. Tap **Publish**.
4. The announcement appears in the list immediately and is visible to the selected audience the next time they open the app.

#### Archiving an announcement
1. Tap the **Archive** button on the row.
2. The announcement is marked inactive and disappears from the dealer-facing UI.
3. Archived announcements are kept in the system for audit purposes but no longer shown.

Use announcements for things like:
- Network-wide policy changes
- Product updates
- Pricing changes (with effective date)
- Holiday schedules
- System maintenance windows

### Section D: System PINs

Manages the master PINs that control access to each mode of the app. Only Owners can change PINs.

**The list shows every PIN slot** with:
- **Slot label** (e.g., "Corporate PIN", "Installer PIN", "Sales PIN")
- **Set / Not set status badge**
- **Change PIN button**

#### Changing a PIN
1. Tap **Change PIN** on the slot you want to update.
2. The **Change PIN Sheet** opens with these fields:
   - **Current PIN** — required if a PIN is already set on this slot (for verification)
   - **New PIN** — must be exactly 4 digits
   - **Confirm new PIN** — must match the new PIN
3. Tap **Save**.
4. The system verifies the current PIN (if applicable), then sets the new PIN.
5. The list refreshes and the slot shows the new "Set" status.

**Important:** Changing a PIN takes effect immediately. Anyone using the old PIN will be locked out. Always coordinate PIN changes with the affected users in advance.

---

## 8. Quick Reference

| I want to... | Tab | Section |
|---|---|---|
| **See total network revenue this month** | Network | Header metrics |
| **Find a stalled job across all dealers** | Pipeline | Filter by status; look for red stall indicators |
| **See which dealer has the most active jobs** | Network | Dealer cards (sort by "Active" pill) |
| **Look at a specific job in detail** | Pipeline | Tap any job card |
| **Check who's wasting the most LED strip** | Warehouse | Network waste intelligence |
| **Spot inventory shortfalls before they hit jobs** | Warehouse | Reorder triggers |
| **Add a new dealer to the network** | Admin | Dealer Management → Add |
| **Suspend a dealer without deleting them** | Admin | Dealer Management → Active toggle |
| **Change the network's default pricing** | Admin | Pricing Defaults |
| **Push a message to all dealers** | Admin | Network Announcements → New |
| **Rotate a master PIN** | Admin | System PINs (Owner only) |

---

**Need help?** This dashboard is internal-only. Contact the Owner directly for role escalation or system issues.
