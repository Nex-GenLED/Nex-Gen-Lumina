# Dealer Inventory Dashboard — Guide

**Audience:** Dealers and dealer admins managing material stock and tracking install efficiency

This guide covers the Inventory Dashboard inside the Dealer Dashboard — what each section shows, how to keep your stock counts accurate, and how to use waste data to improve your business over time.

---

## 1. Accessing the Inventory Tab

The Inventory Dashboard lives inside the **Dealer Dashboard**.

1. Sign in to **Sales Mode** or **Installer Mode** with your dealer PIN.
2. Tap **Dashboard** (or **Dealer Dashboard** from the installer landing screen).
3. Navigate to the **Inventory** tab.

The screen is divided into **5 stacked sections**. Some are fully functional today; others are placeholders that will light up in future updates as supporting data is wired through. Each section is described below.

---

## 2. Section 1: On Hand

**Status:** Fully functional today.

This is your live stock count for every material in your dealer catalog. Each row represents one item.

### What each row shows

| Element | Meaning |
|---|---|
| **Stock icon** (left) | Cyan box = normal stock; amber warning triangle = low stock |
| **Material name** | The product name from your catalog (e.g., "RGBW LED Strip — Roofline") |
| **Low stock warning** | Amber text reading **"Low stock — at or below reorder threshold of X {unit}"** if you're at or under the threshold |
| **Reorder threshold note** | Shown when stock is healthy: "Reorder threshold: X {unit}" |
| **On-hand quantity** (right, large white) | Current count |
| **+ Receive Stock button** | Tap to record incoming inventory |

### Sorting and indicators

- **Low-stock items sort to the top** automatically so you see what needs attention first.
- The card border turns **amber** for low-stock items and **cyan** for normal stock.
- Tap any row to expand it (in future updates this will show stock movement history).

### Recording received stock

When a shipment arrives, tap the **+ Receive Stock** button on any item.

1. A dialog opens titled **"Receive stock"**.
2. The current on-hand count is shown for reference.
3. Type the **quantity received** in the input field. Decimals are allowed (e.g., `100.5` ft of wire).
4. Tap **Receive**.
5. A snackbar confirms: **"Received {quantity} {unit} of {item name}"**.
6. The on-hand count updates immediately and the stock movement is logged.

> **Tip:** Receive stock as soon as the shipment arrives, not at the end of the week. Real-time stock counts are what make the dashboard useful.

---

## 3. Section 2: Committed to Active Jobs

**Status:** Coming in a future update.

When live, this section will show how much of each material is currently spoken for by jobs that are signed but not yet installed. For example, if you have 5 jobs in **Pre-wire scheduled** status that collectively need 800 feet of LED strip, this section will show that 800 feet is "committed".

### Why it's not live yet
The current estimate breakdown stores line items by description, not by SKU. To compute committed inventory we need to bridge the estimate's line items to the dealer's catalog SKUs. That bridge is on the roadmap.

### What you'll see today
A placeholder card with an amber warning icon explaining that the **inventory bridge is required** before this section can show real numbers.

---

## 4. Section 3: Available

**Status:** Coming in a future update.

This section will show **Available = On Hand − Committed** for every material. It's the most useful number for ordering decisions because it tells you what you have free and clear after every signed job is satisfied.

### Why it's not live yet
This section depends entirely on Section 2. Once the inventory bridge is built, both sections light up at the same time.

### What you'll see today
A placeholder card explaining the formula and noting that it will populate when Section 2 is complete.

---

## 5. Section 4: Waste Intelligence

**Status:** Fully functional today (as soon as you have completed installs with material check-in data).

This is the most valuable section for improving your business. It tells you which materials your install crews waste, how that waste is trending over time, and which items to focus on for improvement.

### Where the data comes from

Every time a Day 2 install team finishes a job and goes through the wrap-up sequence, **Step 2 (Material Check-In)** records:
- The estimated quantity for each material
- The quantity returned (unused)
- The computed quantity used
- The waste percentage

Waste Intelligence aggregates this data across every completed job to give you per-material averages and trends.

### What each row shows

| Column | Meaning |
|---|---|
| **Material** | Item name with sample count below in smaller text |
| **Avg waste %** | Average waste across all completed jobs for this item |
| **Trend arrow** | Direction of waste over time |

### How waste % is calculated

For each completed install:
- **Waste % = (Returned / Estimated) × 100**

For example, if the estimate called for 200 ft of wire and the installer returned 30 ft:
- Used = 170 ft
- Waste = 30 / 200 = **15%**

The dashboard averages this across every completed install for that material.

### Trend arrows

The trend arrow compares your **5 most recent installs** against all earlier installs for that material:

| Arrow | Color | Meaning |
|---|---|---|
| **▲ Trending up** | Red | Waste is getting worse over time — bad |
| **▼ Trending down** | Green | Waste is improving — good |
| **— Flat** | Gray | Waste is roughly steady (within 0.5 percentage points) |
| **— (dash)** | Neutral gray | Not enough data — fewer than 3 sample jobs |

### Minimum sample threshold

Trends only appear once you have at least **3 completed installs** for a given material. Below that, the trend column shows a dash and the average is shown but should be taken with a grain of salt.

The more installs you complete, the more accurate the waste data becomes. After 10–20 installs of each material, the trends become statistically meaningful.

### Color coding

The waste % itself is color-coded so you can spot problems at a glance:

| Waste % | Color | Action |
|---|---|---|
| **< 8%** | Green | Healthy. Estimates are well-tuned. |
| **8% – 14%** | Amber | Watch this item. Consider tightening the estimate or training installers. |
| **≥ 15%** | Red | Investigate. Either the estimate is padded or installers are wasting material. |

### Sort order

Items are sorted **worst-first** — highest waste % at the top — so the items most in need of attention show up immediately.

---

## 6. Section 5: Reorder Suggestions

**Status:** Coming in a future update.

When live, this section will calculate per-job average usage for each material (using your waste data) and recommend reorder quantities based on:
- Your current on-hand stock
- Your active job pipeline
- Historical per-job consumption averages

### Why it's not live yet
This depends on Section 2 being complete. Once committed inventory and per-job usage are wired up, the system can compute reorder triggers automatically.

### What you'll see today
A placeholder card explaining what's coming. In the meantime, use **Section 1: On Hand** with the manual low-stock indicators and **Section 4: Waste Intelligence** to make ordering decisions yourself.

---

## 7. Why Waste Data Matters

The Waste Intelligence section is the single most important dealer-facing analytics tool in Lumina. Here's why:

### It tells you where money is leaking
Every foot of wire, clip, or strip that gets thrown away is cash you bought and didn't sell. A 15% waste rate on a $30k/month material spend is **$4,500/month walking to the trash**. That's an entire technician's pay.

### It exposes estimate inaccuracy
If your salesperson consistently estimates 200 ft of wire for a job that uses 150 ft, your prices are inflated and your margins look better than reality. Waste data reveals this so you can tighten estimates and either lower prices to win more jobs or pocket the difference as cleaner margin.

### It surfaces installer training opportunities
If one type of material has high waste across all jobs, the issue is the estimate. If waste varies wildly job-to-job, the issue is the installer. The trend arrow helps you tell the difference.

### How to improve waste over time

1. **Be honest in the wrap-up.** The data is only useful if installers report returns accurately. If you suspect under-reporting, audit a few jobs in person.
2. **Review the dashboard weekly.** Look for items in the red/amber bands.
3. **Adjust estimates** for items consistently over 12% waste. Tighten the calculation in your dealer pricing.
4. **Train installers** on the items with worst trends. Often it's installation technique (e.g., wasted strip from poor cut planning).
5. **Watch the trend arrow** after making changes. Improvement will show up within 5 completed jobs.
6. **Compare to network averages** in the corporate Warehouse tab if you have access — your dealer may be above or below the network norm for a given item.

A dealer that gets waste under 8% across the board on a material-heavy product like LED strip is reclaiming several percentage points of margin straight to the bottom line.

---

## 8. Quick Reference

| I want to... | Do this |
|---|---|
| **Check current stock** | Section 1 — top of the screen |
| **Record incoming inventory** | Section 1 → tap **+ Receive Stock** on the item |
| **See which items are low** | Section 1 — low items are sorted to the top with amber borders |
| **See which materials are wasteful** | Section 4 — sorted worst-first |
| **See if waste is improving** | Section 4 — check the trend arrow |
| **Decide what to reorder** | Use Section 1 (low stock indicators) plus Section 4 (waste trends) until Section 5 is live |

---

**Need help?** Contact your Nex-Gen LED corporate contact.
