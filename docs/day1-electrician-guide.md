# Day 1 Electrician — Field Guide

**Audience:** Electricians running Day 1 wiring prep on a Lumina installation.

Log in, read the blueprint, do the work, check out clean so Day 2 can finish. That's the job.

## What you'll need

- Your 4-digit **Installer PIN** (dealer code + installer code)
- The Lumina app on your phone
- Your materials — wire, power supplies, injection connectors, brackets (exactly what's on the blueprint materials list)
- Your standard electrical tools
- Phone signal or Wi-Fi at the job site (for checking off tasks)

---

## 1. Log in

Day 1 happens inside **Installer Mode**, gated by a 4-digit PIN.

### PIN format

- Digits 1–2: your **dealer code** (e.g., `42`)
- Digits 3–4: your **installer code** (e.g., `07`)
- Together: `4207`

You got this from your dealer admin at onboarding.

### Steps

1. Open the Lumina app
2. Tap the **Lumina logo** 5 times on the login screen — the Staff PIN screen opens
3. Type your 4-digit PIN
4. The app verifies against your dealer's records and drops you into Installer Mode

### Session timeout

- Sessions run **30 minutes** of activity
- Warning pops **5 minutes before** it ends — tap anything to extend
- If you get logged out, sign back in. Your work is saved.

---

## 2. Open the Day 1 Queue

From the Installer Landing screen, tap **Day 1 Queue**.

### What's in the queue

Every job for your dealer that's ready for pre-wire:

- **Signed** (cyan badge) — customer signed, Day 1 not yet scheduled
- **Pre-wire scheduled** (amber badge) — Day 1 date locked in

Newest jobs at the top.

### Card fields

| Element | Meaning |
|---|---|
| **Customer name** | Who the job is for |
| **Address** | Full street, city, state, zip |
| **Status badge** | Cyan = Signed, amber = Pre-wire scheduled |
| **Day 1: {date}** | Shown only if Day 1 is scheduled |
| **Reschedule** | Inline button next to the date |
| **Schedule Day 1** | Shown only if Day 1 hasn't been scheduled yet |

---

## 3. Schedule Day 1

For any **Signed** job that's not yet scheduled:

1. Tap **Schedule Day 1** on the card
2. Pick the date you'll be on-site (today → 365 days out)
3. Tap **OK**
4. Snackbar confirms: **"Day 1 scheduled for {date}"**

Job moves from **Signed** to **Pre-wire scheduled**. Customer gets an SMS confirming the date immediately, plus a reminder SMS the night before.

To change a date: tap **Reschedule** next to the existing date, pick a new one.

---

## 4. The Day 1 Blueprint screen

Tap any job card to open its **Day 1 Blueprint**. Everything you need is on one scroll.

### Section 1 — Home photo with channel overlays

- Front-of-home photo with colored polylines for each channel run
- Tap the photo to expand full-screen
- **Channel chips** below — tap to highlight that run on the overlay

Use this to orient before you start running wire.

### Section 2 — Controller mount

Where the controller goes.

- **Location description** — specific text like "Garage left interior wall, 3 feet from breaker panel." This is what the salesperson promised the customer.
- **Mount photo** — if captured
- **Mount type** — Interior or exterior

All wiring runs back to this point. Mount the controller box first.

### Section 3 — Per-channel detail cards

For every channel:

| Field | What you need to know |
|---|---|
| **Channel number + label** | Header — "Channel 1 — Front Roofline" |
| **Linear footage** | Total length of the run |
| **Run direction** | Which way Day 2 will feed the strip (L→R, etc.) |
| **Start description + photo** | Where the run begins |
| **End description + photo** | Where the run ends |
| **Injection points list** | Every power injection point on this run |

#### Injection points

For each one:

- **Location description** — where on the run (e.g., "Corner of deck behind downspout")
- **Distance from start** — feet from the beginning of the run
- **Wire gauge** — recommended size based on distance from controller:
  - **Direct** (0 ft) — connector only
  - **14/2** — up to 30 ft
  - **12/2** — up to 90 ft
  - **10/2** — up to 140 ft
  - **EXCEEDS 140ft** — stop, call your dealer admin
- **Photo** — if captured

### Section 4 — Materials list

Power and hardware only on Day 1 — wire, power supplies, injection connectors, mounting brackets.

> **LED strip is NOT delivered on Day 1.** It arrives with the Day 2 install team. Day 1 is wiring prep only.

Each row shows item name, category (POWER or HARDWARE), and quantity needed.

**Bring exactly what's on the list.** Short on anything? Call your dealer admin before you arrive.

### Section 5 — Task checklist

Auto-generated list of every action you need to perform. Grouped by type:

- **Mount the controller** — one task
- **Wiring tasks** — one per channel, e.g., "Run wire through left corner of house to right corner above garage — 120ft"
- **Injection tasks** — one per injection point, e.g., "Cap and label at corner of deck, 60ft"
- **Verification task** — "Verify all wires are accessible outside wall for Day 2"

Tap a checkbox as you complete work. Green check appears.

Progress shows as **"X of N tasks completed"** with a progress bar — cyan while working, green at 100%.

---

## 5. Do the work

Standard Day 1 sequence:

1. **Arrive on-site.** Greet the customer. Confirm gate codes, dogs, parking from the salesperson notes (visible on the Job Detail screen).
2. **Mount the controller** at the specified location. Check the task.
3. **Run wire from the controller out to each channel start point**, then along the channel path to the end. Use the start/end descriptions and the channel polyline as your guide.
4. **At each injection point**, run a separate dedicated wire from the controller (or a power supply mount) and **cap and label** it clearly. Labels match channel number + injection number.
5. **Every wire end must be accessible outside the wall.** Day 2 needs to grab wires and connect them to the LED strip — they can't be inside the wall, behind sheetrock, or hidden behind eaves.
6. **Check tasks off as you go.**

> **The Day 1 rule:** Every wire — controller, channel, injection — must be accessible outside the wall before you check out. Miss this, and Day 2 has to cut into walls.

---

## 6. Mark Day 1 complete

When every task is checked, **Mark Day 1 complete** turns green.

### Check-out is blocked until all tasks are checked

- Any unchecked task → button disabled, reads **"Complete all tasks to mark complete"**
- The "Verify all wires are accessible outside wall for Day 2" task is in this list. You can't check out without confirming it.

### Check out

1. Tap **Mark Day 1 complete**
2. Confirmation dialog asks for your name (or installer code)
3. Type it and tap **Confirm**
4. The app updates the job:
   - Status: **Pre-wire scheduled** → **Pre-wire complete**
   - Your name recorded as Day 1 tech
   - Completion timestamp saved
5. Snackbar: **"Day 1 complete! Job ready for Day 2."**
6. You're back in the Day 1 Queue. The job has moved to the Day 2 team's queue.

---

## 7. What the customer gets

The instant you mark Day 1 complete, the customer gets an SMS:

> *"Great news, {first name}! Wiring prep is complete at your home. Your light installation day is coming soon — we'll text you the night before. — {dealer sign-off}"*

Sent automatically. Don't send anything manually.

Standard reminder SMS goes out the night before Day 2, once Day 2 is scheduled.

---

## 8. Critical Day 1 rules

Break these and Day 2 fails:

| Rule | Why |
|---|---|
| **Every wire accessible outside the wall.** | Day 2 can't install if they have to cut walls. |
| **Label every injection wire** — channel number + position. | Unlabeled wires waste hours. |
| **Mount the controller exactly where the blueprint says.** | The customer agreed to that location. Moving it means re-quoting. |
| **Use the wire gauge the blueprint lists.** | Undersized wire = voltage drop, dim or off-color LEDs at the end of the run. |
| **Don't skip the "verify wires accessible" task.** | Walk the job and physically touch every wire end before you tap it. |
| **Bring exactly the materials on the list.** | Day 1 is wiring only. LED strip arrives on Day 2. |
| **Check off tasks as you go, not at the end.** | If you're interrupted, the next person knows where you left off. |

---

## What success looks like

- Controller mounted at the exact blueprint location
- Every channel wire run from controller to start, along the path, to the end
- Every injection wire capped and labeled with channel number and position
- Every wire end accessible outside the wall (you physically touched each one)
- Every task in the checklist checked
- **Mark Day 1 complete** tapped; job moved to the Day 2 queue
- Customer received the automatic SMS confirming wiring prep is done

## If something isn't working

**"The job isn't in my queue."**
Customer hasn't signed yet, or the job is assigned to a different dealer. Confirm with your dealer admin.

**"I can't tap Mark Day 1 complete."**
Some tasks are still unchecked. Scroll up, find the task without a green check, finish it, check it.

**"Wire gauge says EXCEEDS 140ft."**
Stop. Call your dealer admin. The controller location may need to move closer to the run, or a supplemental power supply may be needed mid-run. Don't install with under-rated wire.

**"The home photo doesn't match what I see on-site."**
Landscaping or paint may have changed. Match the channel start/end descriptions to physical features (corners, downspouts) rather than relying only on the photo.

**"I forgot to schedule Day 1 before showing up."**
Open the Day 1 Queue, find the job, tap **Schedule Day 1**, pick today. The customer gets the SMS automatically.

**"I need to leave the job partially done."**
Check off only the tasks you actually completed. **Do not** mark Day 1 complete. Job stays in **Pre-wire scheduled**. You or another electrician picks it up next visit.

**"PIN won't work."**
Confirm all 4 digits. If you've been locked out after 5 failed attempts, wait 30 seconds or dismiss and reopen the Staff PIN screen. If it still won't work, your dealer admin needs to confirm your installer account is active.

---

**Need help?** Call your dealer admin or your Nex-Gen LED LLC corporate contact.
