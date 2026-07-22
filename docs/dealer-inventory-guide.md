# Dealer Inventory Dashboard — Guide

**Audience:** Dealers and dealer admins managing material stock and tracking install efficiency.

Your inventory is money sitting in boxes. The Inventory Dashboard tells you how much of it you have, how much is walking out the door as waste, and which materials are quietly eating into your margin — so you can fix it. Permanent residential and commercial lighting that works as hard as you do, and the dealers who stay profitable are the ones who know what's happening in their stockroom.

## What you'll need

- The Lumina app on your phone or tablet
- Your **Sales PIN** or **Installer PIN**
- A few minutes each week to keep on-hand counts current
- Completed installs with material check-in data for the Waste Intelligence section to populate

---

## 1. Getting to the Inventory tab

The Inventory Dashboard lives inside the **Dealer Dashboard**.

1. Sign in to Sales Mode or Installer Mode with your dealer PIN
2. Tap **Dashboard** (or **Dealer Dashboard** from the installer landing screen)
3. Tap the **Inventory** tab

The screen is 5 stacked sections. Some are fully functional today; others are placeholders that light up in future updates as supporting data wires through. Each section is described below.

---

## 2. Section 1 — On Hand

**Status:** fully functional today.

Your live stock count for every material in your dealer catalog. One row per item.

### What each row shows

| Element | Meaning |
|---|---|
| **Stock icon** (left) | Cyan box = normal; amber warning triangle = low stock |
| **Material name** | Product name from your catalog (e.g., "RGBW LED Strip — Roofline") |
| **Low stock warning** | Amber text: **"Low stock — at or below reorder threshold of X {unit}"** if you're at or under the threshold |
| **Reorder threshold note** | Shown when stock is healthy: "Reorder threshold: X {unit}" |
| **On-hand quantity** (right, large white) | Current count |
| **+ Receive Stock button** | Tap to log incoming inventory |

### Sorting and indicators

- **Low-stock items sort to the top** automatically — what needs attention shows up first
- Card border turns **amber** for low-stock and **cyan** for normal
- Tap any row to expand (future updates will show stock movement history)

### Recording received stock

When a shipment arrives, tap **+ Receive Stock** on the item.

1. Dialog opens: **"Receive stock"**
2. Current on-hand count shown for reference
3. Type the **quantity received** — decimals are allowed (e.g., `100.5` ft of wire)
4. Tap **Receive**
5. Snackbar: **"Received {quantity} {unit} of {item name}"**
6. On-hand count updates immediately and the stock movement is logged

<div></div>

> **Tip:** Log receipts as the shipment arrives, not at the end of the week. Real-time counts are what make the dashboard useful.

---

## 3. Section 2 — Committed to Active Jobs

**Status:** coming in a future update.

When live, this will show how much of each material is spoken for by jobs that are signed but not yet installed. Five jobs in **Pre-wire scheduled** status that collectively need 800 ft of LED strip? This section will show that 800 ft is "committed."

### Why it's not live yet

The current estimate breakdown stores line items by description, not by SKU. To compute committed inventory we need to bridge the estimate's line items to your catalog SKUs. That bridge is on the roadmap.

### What you'll see today

A placeholder card with an amber warning icon explaining that the **inventory bridge is required** before this section can show real numbers.

---

## 4. Section 3 — Available

**Status:** coming in a future update.

Will show **Available = On Hand − Committed** for every material. The most useful number for ordering decisions — what you have free and clear after every signed job is satisfied.

### Why it's not live yet

Depends entirely on Section 2. Once the inventory bridge is built, both sections light up at the same time.

### What you'll see today

A placeholder card explaining the formula and noting that it will populate when Section 2 is complete.

---

## 5. Section 4 — Waste Intelligence

**Status:** fully functional today (as soon as you have completed installs with material check-in data).

The most valuable section for improving your business. Which materials your install crews waste, how that waste is trending, and which items to focus on.

### Where the data comes from

Every Day 2 wrap-up Step 2 (Material Check-In) records:

- Estimated quantity per material
- Returned (unused) quantity
- Computed used quantity
- Waste percentage

Waste Intelligence aggregates this across every completed job for per-material averages and trends.

### What each row shows

| Column | Meaning |
|---|---|
| **Material** | Item name with sample count below in smaller text |
| **Avg waste %** | Average waste across all completed jobs for this item |
| **Trend arrow** | Direction of waste over time |

### How waste % is calculated

Per completed install: **Waste % = (Returned / Estimated) × 100**

Example: estimate called for 200 ft of wire, installer returned 30 ft.
- Used = 170 ft
- Waste = 30 / 200 = **15%**

The dashboard averages this across every completed install for that material.

### Trend arrows

The trend arrow compares your **5 most recent installs** against all earlier installs for that material:

| Arrow | Color | Meaning |
|---|---|---|
| **▲ Trending up** | Red | Waste is getting worse over time — bad |
| **▼ Trending down** | Green | Waste is improving — good |
| **— Flat** | Gray | Roughly steady (within 0.5 percentage points) |
| **— (dash)** | Neutral gray | Not enough data — fewer than 3 sample jobs |

### Minimum sample threshold

Trends only appear once you have at least **3 completed installs** for a material. Below that, the trend column shows a dash and the average should be taken with a grain of salt.

More installs → more accurate data. After 10–20 installs of each material, the trends become statistically meaningful.

### Color coding

The waste % is color-coded so you can spot problems at a glance:

| Waste % | Color | Action |
|---|---|---|
| **< 8%** | Green | Healthy. Estimates are well-tuned. |
| **8% – 14%** | Amber | Watch this item. Consider tightening the estimate or training installers. |
| **≥ 15%** | Red | Investigate. Either the estimate is padded or installers are wasting material. |

### Sort order

Items are sorted **worst-first** — highest waste % at the top. What needs attention shows up immediately.

---

## 6. Section 5 — Reorder Suggestions

**Status:** coming in a future update.

When live, this will calculate per-job average usage for each material (using your waste data) and recommend reorder quantities based on:

- Current on-hand stock
- Active job pipeline
- Historical per-job consumption averages

### Why it's not live yet

Depends on Section 2. Once committed inventory and per-job usage are wired, the system can compute reorder triggers automatically.

### What you'll see today

Placeholder card explaining what's coming. For now, use **Section 1** (low-stock indicators) plus **Section 4** (waste trends) to make ordering decisions.

---

## 7. Why waste data matters

Waste Intelligence is the single most important dealer-facing analytics tool in Lumina. Here's why.

### It tells you where money is leaking

Every foot of wire, clip, or strip thrown away is cash you bought and didn't sell. A 15% waste rate on $30k/month material spend is **$4,500/month walking to the trash** — an entire technician's pay.

### It exposes estimate inaccuracy

If your salesperson consistently estimates 200 ft of wire for a job that uses 150 ft, your prices are inflated and your margins look better than reality. Waste data reveals this so you can either tighten estimates and win more jobs at lower prices, or pocket the difference as cleaner margin.

### It surfaces installer training opportunities

If one material has high waste across all jobs, the issue is the estimate. If waste varies wildly job-to-job, the issue is the installer. The trend arrow helps you tell which.

### How to improve waste over time

1. **Be honest in wrap-up.** Data is only useful if installers report returns accurately. If you suspect under-reporting, audit a few jobs in person.
2. **Review weekly.** Look for items in the red/amber bands.
3. **Adjust estimates** for items consistently over 12% waste. Tighten the calculation in your dealer pricing.
4. **Train installers** on items with worst trends. Usually it's installation technique (poor cut planning for strip, for example).
5. **Watch the trend arrow** after making changes. Improvement shows up within 5 completed jobs.
6. **Compare to network averages** in the corporate Warehouse tab if you have access — your dealer may be above or below the network norm.

A dealer that gets waste under 8% across the board on a material-heavy product like LED strip reclaims several percentage points of margin straight to the bottom line.

---

## 8. Quick reference

| I want to... | Do this |
|---|---|
| Check current stock | Section 1 — top of the screen |
| Record incoming inventory | Section 1 → tap **+ Receive Stock** on the item |
| See which items are low | Section 1 — low items sort to the top with amber borders |
| See which materials are wasteful | Section 4 — sorted worst-first |
| See if waste is improving | Section 4 — check the trend arrow |
| Decide what to reorder | Section 1 (low stock) + Section 4 (waste trends) until Section 5 is live |

---

## What success looks like

- On-hand counts match what's physically on your shelves within a day of any shipment
- Low-stock items in Section 1 get reordered before they hit zero
- Every high-spend material in Section 4 sits in the green (< 8%) or green-trending-down
- Red trend arrows go green within 5 completed jobs after you adjust the estimate or train the installer
- Month-over-month material spend drops while job volume stays flat or grows — that's waste reclaimed as margin

## If something isn't working

**"The On Hand count is wrong."**
The most common cause is a shipment that wasn't logged. Tap **+ Receive Stock** on the item and enter the missing quantity. If the count is too high, contact your Nex-Gen LED LLC corporate contact — manual corrections need backend access.

**"Section 4 is empty."**
Waste Intelligence needs completed installs with material check-in data. If you've only had a few recent jobs, wait until you have at least 3 completed installs for the material in question. Below that threshold, the section shows a dash.

**"A material shows 30% waste that seems way too high."**
Two possibilities. (1) The estimate is padded — the salesperson is consistently estimating more than needed. Tighten it. (2) The installer is wasteful. Check if the trend is worse than other installers on the same material. Train accordingly.

**"An installer is reporting 0% waste on every job."**
That's probably dishonest. True 0% is nearly impossible. Audit the installer on the next install — count materials yourself. The data is only useful if the reports are honest.

**"I just received a shipment but can't find the item in Section 1."**
The item isn't in your catalog yet. Contact your Nex-Gen LED LLC corporate contact to add it. Once added, it'll appear in Section 1 and you can log the receipt.

---

**Need help?** Contact your Nex-Gen LED LLC corporate contact.
