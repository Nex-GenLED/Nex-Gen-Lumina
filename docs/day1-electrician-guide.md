# Day 1 Electrician — Field Guide

**Audience:** Electricians performing Day 1 wiring prep on a Lumina installation

This guide covers everything you need to know on Day 1: getting into the app, reading the blueprint, doing the work, and checking out cleanly so the Day 2 install team can finish the job.

---

## 1. Logging In

Day 1 work happens inside **Installer Mode**, which is gated behind a 4-digit PIN.

### PIN format
- **Digits 1–2:** Your dealer code (e.g., `42`)
- **Digits 3–4:** Your personal installer code (e.g., `07`)
- Together: `4207`

You'll get this PIN from your dealer admin during onboarding.

### How to log in
1. Open the Lumina app.
2. From the main launch screen, tap **Installer Mode**.
3. Tap **Enter Installer PIN**.
4. Type your 4-digit PIN on the keypad.
5. The app verifies the PIN against your dealer's records and lets you in.

### Session timeout
- Your session stays active for **30 minutes** of activity.
- A warning will pop up **5 minutes before** the session ends so you can extend it.
- Tap any button or scroll to reset the timer.
- If you get logged out, just sign back in — your work is always saved.

---

## 2. The Day 1 Queue

After you log in, the **Installer Landing** screen shows your action tiles. Tap **Day 1 Queue**.

### What the Day 1 Queue shows

The queue lists every job for your dealer that's ready for pre-wire — specifically, jobs in one of these statuses:

- **Signed** (cyan badge) — Customer has signed but Day 1 isn't scheduled yet
- **Pre-wire scheduled** (amber badge) — Day 1 has a date locked in

Newest jobs appear at the top.

### What each card shows

| Card element | Meaning |
|---|---|
| **Customer name** (top, bold) | Who the job is for |
| **Address** (below name) | Full street, city, state, zip |
| **Status badge** (top-right) | Color-coded — cyan = Signed, amber = Pre-wire scheduled |
| **Day 1: {date}** (cyan calendar icon) | Shown only if Day 1 is scheduled |
| **Reschedule** | Inline text button next to the date |
| **Schedule Day 1** button | Shown only if Day 1 hasn't been scheduled yet |

---

## 3. Scheduling Day 1

For any job that's **Signed** but not yet scheduled, tap the **Schedule Day 1** button on the card.

1. A dark date picker opens.
2. Pick the date you'll be on-site (today through 365 days out).
3. Tap **OK**.
4. A confirmation snackbar appears: **"Day 1 scheduled for {date}"**.

The job's status moves from **Signed** to **Pre-wire scheduled**, and the customer immediately receives an SMS confirming the date. The night before the visit, they'll automatically receive a reminder SMS.

To change a date, tap **Reschedule** next to the existing date and pick a new one.

---

## 4. The Day 1 Blueprint Screen

Tap any job card to open its **Day 1 Blueprint**. This is the main work screen — everything you need to do the job is on one scroll.

### Section 1: Home Photo with Channel Overlays

At the top you'll see the **front-of-home photo** the salesperson captured. Drawn on top of the photo are colored polylines showing each channel run.

- **Tap the photo** to expand it full-screen for a closer look.
- Below the photo is a row of **channel chips**. Each chip shows the channel number and label (e.g., "1 — Front Roofline"). Tap a chip to highlight that run on the overlay.

This is your map of the entire job. Use it to orient yourself before you start running wire.

### Section 2: Controller Mount

This card tells you where the controller goes:

- **Location description** — A specific text description like "Garage left interior wall, 3 feet from breaker panel". This is what the salesperson promised the customer.
- **Mount photo** — A picture of the spot (if the salesperson captured one).
- **Mount type** — Interior or exterior.

This is the single point that all wiring runs back to. Mount the controller box here first.

### Section 3: Per-Channel Detail Cards

For every channel on the job, you'll see a detail card with:

| Field | What you need to know |
|---|---|
| **Channel number + label** | Header — "Channel 1 — Front Roofline" |
| **Linear footage** | Total length of the run |
| **Run direction** | Which way the install team will feed the strip on Day 2 (Left → Right, etc.) |
| **Start description + photo** | Where the run begins |
| **End description + photo** | Where the run ends |
| **Injection points list** | Every power injection point on this run |

#### Reading injection points
For each injection point, you'll see:
- **Location description** — where on the run it lives (e.g., "Corner of deck behind downspout")
- **Distance from start** — feet from the beginning of the run
- **Wire gauge** — the recommended wire size based on distance from the controller:
  - **Direct** (0 ft) — connector only
  - **14/2** (up to 30 ft)
  - **12/2** (up to 90 ft)
  - **10/2** (up to 140 ft)
  - **EXCEEDS 140ft** — flag this immediately, the controller may need to be relocated
- **Photo** of the location (if captured)

### Section 4: Materials List

Below the channels you'll see the **Materials** card. On Day 1, this shows only **Power** and **Hardware** items — wire, power supplies, injection connectors, mounting brackets.

> **Important:** The LED strip itself is **NOT** delivered on Day 1. The strip arrives with the Day 2 install team. Your job is wiring prep only.

Each row shows the item name, the category (POWER or HARDWARE), and the quantity needed.

**Bring exactly what's on this list.** If you're short on anything, contact your dealer admin before you arrive.

### Section 5: Task Checklist

The bottom section is the **Task Checklist** — an auto-generated list of every action you need to perform. Tasks are grouped by type:

- **Mount the controller** — one task
- **Wiring tasks** — one per channel, e.g., "Run wire through left corner of house to right corner above garage — 120ft"
- **Injection tasks** — one per injection point, e.g., "Cap and label at corner of deck, 60ft"
- **Verification task** — "Verify all wires are accessible outside wall for Day 2"

Each task is a checkbox. As you complete work, tap the checkbox to mark it done. A green check circle appears.

The screen shows your progress as **"X of N tasks completed"** with a colored progress bar — cyan while in progress, green when complete.

---

## 5. Doing the Work

Here's the typical Day 1 sequence:

1. **Arrive on-site.** Greet the customer. Confirm gate codes, dog warnings, and parking based on the salesperson notes (visible on the Job Detail screen if needed).
2. **Mount the controller** at the location specified. Check the box on the task list.
3. **Run wire from the controller out to each channel start point**, then along the channel path to the end. Use the start/end descriptions and the channel polyline overlay as your guide.
4. **At each injection point**, run a separate dedicated wire from the controller (or from a power supply mount) and **cap and label** it clearly. Labels should match the channel number and injection number.
5. **Make sure every wire end is accessible from the outside of the wall.** Day 2 needs to grab these wires and connect them to the LED strip — they cannot be inside the wall, behind sheetrock, or hidden behind eaves.
6. **Check off each task** in the app as you complete it.

> **The most important Day 1 rule:** Every wire — controller wires, channel wires, injection wires — must be **accessible outside the wall** before you check out. If Day 2 has to cut into the wall to find a wire, the install will be delayed and the customer will be unhappy.

---

## 6. Marking Day 1 Complete

When you've finished all the wiring and checked off every task, the **Mark Day 1 complete** button at the bottom of the screen will become active (green).

### Check-out is blocked until all tasks are checked
- If any task is unchecked, the button stays disabled and reads **"Complete all tasks to mark complete"**.
- The "Verify all wires are accessible outside wall for Day 2" task is part of this checklist — you cannot check out without confirming it.

### Tapping Mark Day 1 complete
1. A confirmation dialog asks for your name (or your installer code).
2. Type your name and tap **Confirm**.
3. The app updates the job:
   - Status moves from **Pre-wire scheduled** to **Pre-wire complete**.
   - Your name is recorded as the Day 1 technician.
   - The completion timestamp is saved.
4. A snackbar confirms: **"Day 1 complete! Job ready for Day 2."**
5. You're returned to the Day 1 Queue. The job has disappeared from your queue and now lives in the Day 2 team's queue.

---

## 7. What the Customer Receives After Day 1

The moment you mark Day 1 complete, the customer automatically receives an SMS that reads roughly:

> *"Great news, {first name}! Wiring prep is complete at your home. Your light installation day is coming soon — we'll text you the night before. — {dealer sign-off}"*

This is sent automatically by the system. You don't need to send anything manually.

The customer also gets the standard reminder SMS the night before Day 2, once Day 2 is scheduled.

---

## 8. Critical Day 1 Rules

These are the rules that, if broken, will cause Day 2 to fail and the customer to be unhappy:

| Rule | Why it matters |
|---|---|
| **Every wire must be accessible outside the wall.** | Day 2 cannot install lights if they have to cut into walls to find wires. |
| **Label every injection wire** with channel number and position. | Day 2 needs to know which wire goes to which injection point. Unlabeled wires waste hours. |
| **Mount the controller exactly where the blueprint says.** | The customer agreed to that location. Moving it requires re-quoting. |
| **Use the wire gauge listed on the blueprint.** | Undersized wire causes voltage drop and the LEDs at the end of the run will be dim or off-color. |
| **Don't skip the "verify wires accessible" task.** | This is the final check. Walk the entire job and physically touch every wire end before you tap it. |
| **Bring exactly the materials on the list.** | Day 1 is wiring only. The LED strip arrives on Day 2. |
| **Check off tasks as you go, not at the end.** | If you get interrupted mid-job, the next person on the project knows where you left off. |

---

## 9. Troubleshooting

**The job isn't in my queue.**
The customer hasn't signed yet, or the job is assigned to a different dealer. Confirm with your dealer admin.

**I can't tap "Mark Day 1 complete".**
Some tasks are still unchecked. Scroll up and look for any task without a green check.

**The wire gauge says EXCEEDS 140ft.**
Stop. Call your dealer admin. The controller location may need to move closer to the run, or a supplemental power supply may be needed mid-run. Don't try to install with under-rated wire.

**The home photo doesn't match what I see on-site.**
The customer may have done landscaping or repainted. Match the channel start/end descriptions to physical features (corners, downspouts, etc.) rather than relying on the photo alone.

**I forgot to schedule Day 1 before showing up.**
Open the Day 1 Queue, find the job, tap **Schedule Day 1**, and pick today's date. The customer will get the confirmation SMS — don't worry, the system handles it.

**I need to leave the job partially done.**
Check off only the tasks you actually completed. Do NOT mark Day 1 complete. The job will stay in **Pre-wire scheduled** status. You or another electrician can pick it back up tomorrow.

---

**Need help?** Contact your dealer admin or your Nex-Gen LED corporate contact.
