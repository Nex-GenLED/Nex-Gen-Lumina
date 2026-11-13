# Phone bench plan — build 126 sync reliability (slices A, B and C)

**Written, not run.** Nothing below has contacted a controller.

| | |
|---|---|
| **Account** | **A test account whose only controller is the spare `.179`.** The owner's home account, whose controller is the `.150`, **must not be used for this run**: an automatic re-sync could psave or pdel the `.150`'s corrupted presets. No customer account, ever. Step 0.3 checks the controller the app is talking to and stops the run if it is not the spare. |
| **Controller** | **The spare only: `.179` on the home LAN, WLED 0.15.4, `ESP32_Ethernet`.** The home unit `.150` is **excluded by name**: nothing in this run may write to it. If at any point the app shows `.150` as the controller it is talking to, the run **stops** (step 0.3). |
| **Build** | This build, installed from TestFlight on the iPhone (2.5.10+126 on the login screen it reads `v2.5.10`; the TestFlight number is the one the invite named). Branch `feat/126-candidate`; slice D (`feat/126-sync-readback`) is **not** in it. |
| **Tools** | The iPhone only, plus a browser on the home Wi-Fi for **read-only** looks at the spare: `http://<spare>/json/info`, `http://<spare>/presets.json`, `http://<spare>/json/cfg`. All three are plain GETs that change nothing on the unit. No laptop scripts, no POSTs, no WLED web UI buttons. |
| **Firmware note** | The behaviours were built against 0.15.1 (the home unit's version) and the app does not branch on version (T-F12). A difference on 0.15.4 is a finding, not a pass. |

What this run proves that the suite cannot: that the owed re-sync lands real
timers and a real preset on a real unit, that the queued follow-up's write is
the unit's last word, and that the row and chip say the right thing on a phone.
The app's side is proven by the suite
(`test/features/schedule/schedule_resync_owed_test.dart`,
`schedule_sync_queue_test.dart`, `schedule_sync_cross_slice_126_test.dart`,
`schedule_sync_status_widgets_test.dart`).

## How to read this plan

- Every step is a **phone tap** or a **browser read** of the spare. "Browser:"
  marks a read; everything else is on the phone.
- Every step ends with a **Pass:** line. Write the phone's local time next to
  it in the results table.
- **If a step fails: stop.** Do not tap Retry again, do not repeat the step,
  do not try the next section. Note the phone time, what the row and the chip
  said (word for word), and what the browser reads showed, then stop the run.
  One failed step is a finding to bring back, not something to work around on
  the bench. The only exception is written into the step itself.
- Timing: the automatic re-sync runs only **9:00–15:00 local**. Part 1 must
  run inside that window; Part 2 must run **after 15:00** (or before 9:00).
  Do not move the phone's clock (it breaks sign-in and TestFlight); run the
  two parts at the right times of day instead.
- Timers fire on the unit's own clock. The spare's clock resets when it loses
  power; if `/json/info` shows a `time` in 1970 or hours off, the timer-fire
  checks (1.7, 3.3) will not fire on time and must be marked "not checked",
  not failed.

## 0. Before starting (reads only)

0.1 **Browser:** `/json/info`. *Pass:* `ver` is `0.15.4`, `arch` is `esp32`,
    `ip` ends in `.179`, `name` is the spare's name. Write the name down; it
    must match what the phone shows in 0.3.

0.2 **Browser:** `/json/cfg`. Find `timers` → `ins`. *Pass:* you can see the
    list (it may be empty or hold rows from earlier bench work). Note how many
    rows there are and their `hour`/`min`. Then `/presets.json`. *Pass:* it
    loads; note which numbered slots are present (the app uses slots 10–41).

0.3 Phone: open the app, signed in to the home account, on the home Wi-Fi.
    System tab → the controller entry → details. *Pass:* exactly one
    controller, "IP Address" ends in `.179`, and the name matches 0.1.
    **If it shows `.150`, or more than one controller: STOP. Nothing else in
    this plan may run.**

0.4 Phone: System tab → Remote Access. *Pass:* no bridge is paired (the screen
    offers setup, not a paired bridge). If a bridge is paired, the off-LAN
    steps below would relay through it instead of deferring: **STOP** and
    say so; the plan needs a change, not a workaround.

0.5 Phone: Home and My Schedule. *Pass on a fresh install:* no sync status row
    under the schedule list and no chip on Home (the surfaces render only
    once this install has synced). If the app was installed earlier and has
    synced before, the row and chip may already show "Your schedule is on your
    lights." in green — that is also a pass; write down which.

0.6 Phone: My Schedule. *Pass:* no schedule named for this bench exists yet.
    If an older bench schedule is there, delete it now (tap it → Delete) and
    re-check `/json/cfg` `timers.ins` has no row for it before going on.

## 1. Off-LAN edit, then the LAN-return re-sync (slice B) — inside 9:00–15:00

1.1 Phone: Settings → Wi-Fi → turn Wi-Fi **off** (the phone is now on mobile
    data, off the home LAN). Open the app. *Pass:* the app opens and Home
    renders (it may show the lights as unreachable; that is expected).

1.2 Phone: My Schedule → `+` → pick any pattern from Explore → ON time =
    now + 20 minutes, OFF time = now + 25 minutes, every day → Save.
    *Pass:* the status row reads, word for word,
    "Your schedule hasn't reached your lights yet. It sends when you open the
    app on your home Wi-Fi between 9 am and 3 pm. At other times, tap Retry
    once you're home. · just now" with a **Retry** button; Home shows the chip "Your schedule hasn't
    reached your lights yet." with **Retry**.

1.3 **Browser** (on the home Wi-Fi, a laptop or the phone after 1.5 — read it
    before the phone rejoins if you have a second device; otherwise skip to
    1.4 and read it at 1.6 as "unchanged since 0.2"): `/json/cfg` →
    `timers.ins` is as in 0.2; `/presets.json` is as in 0.2. *Pass:* nothing
    was written while off-LAN.

1.4 Phone: swipe the app away (kill it). Re-open it, still with Wi-Fi off.
    *Pass:* the row and the chip read exactly as in 1.2 (the state survived
    the restart), each with Retry.

1.5 Phone: with the app open on My Schedule, Settings → Wi-Fi → turn Wi-Fi
    **on** and join the home network; return to the app. This is the
    LAN-return trigger. Wait up to 30 seconds. *Pass:* the row ends on
    "Your schedule is on your lights. · just now" in green with **no** Retry;
    Home's chip reads "Your schedule is on your lights." with no Retry.
    *If instead the row still says "hasn't reached your lights yet" after
    60 seconds:* note the phone time (is it inside 9:00–15:00?), do **not**
    tap Retry, and stop.

1.6 **Browser:** `/json/cfg` → `timers.ins`. *Pass:* two new rows for the
    schedule — one at the ON hour/minute and one at the OFF hour/minute, both
    `en: 1`, the ON row's `macro` pointing at a slot between 10 and 41. Then
    `/presets.json`. *Pass:* that slot now exists and holds the pattern (its
    `seg` list has one entry per channel of the spare, not just one).

1.7 Watch the spare at the ON minute. *Pass:* the lights come on with the
    pattern on every channel; at the OFF minute they go off. (The firing is
    the controller's own timer; this only confirms the write was real.)
    If the clock caveat in "How to read this plan" applies, mark "not
    checked" and go on.

1.8 Phone: Home. *Pass:* the chip still reads "Your schedule is on your
    lights." (the timer firing does not change the sync state).

## 2. Held outside the window, then manual Retry (slice B) — after 15:00

2.1 Repeat 1.1 and 1.2 (Wi-Fi off; edit the same schedule: move its ON time
    to now + 20 minutes and save). *Pass:* the row and chip read as in 1.2,
    with Retry.

2.2 Repeat 1.5 (Wi-Fi back on, app open). Wait 60 seconds. *Pass:* the row
    **stays** on "Your schedule hasn't reached your lights yet. …" with Retry
    (the automatic re-sync is held outside 9:00–15:00); the chip likewise.
    *If it went green by itself:* that is a finding (the window did not
    hold); note the phone time and stop.

2.3 **Browser:** `/json/cfg` → `timers.ins`. *Pass:* the schedule's ON row
    still shows the **old** ON time from Part 1 (nothing was written).

2.4 Phone: tap **Retry** on the row (once). Wait up to 30 seconds. *Pass:*
    the row reads "Your schedule is on your lights. · just now" in green
    with no Retry; the chip likewise.

2.5 **Browser:** `/json/cfg` → `timers.ins`. *Pass:* the schedule's ON row
    now shows the **new** ON time.

## 3. Lights ON is not a hold, and the lights-off trigger (slice B) — inside 9:00–15:00

3.1 Phone, on the home Wi-Fi: Home → turn the lights **on** (power button;
    any pattern). *Pass:* the spare lights up.

3.2 Repeat 1.1 and 1.2 (Wi-Fi off; change the schedule's OFF time to
    now + 30 minutes; save). *Pass:* the row and chip read as in 1.2.

3.3 Repeat 1.5 (Wi-Fi back on, app open) with the lights still on. Wait up
    to 30 seconds. *Pass:* the row goes green "Your schedule is on your
    lights." with no Retry — the lights being on did not hold it. You may see
    the strip blink for well under a second during the sync and come back to
    the same pattern; a blink that lasts longer, or the lights ending on a
    different pattern or off, is a finding: note it and stop.

3.4 **Browser:** `/json/cfg` → `timers.ins`. *Pass:* the OFF row shows the
    new OFF time.

3.5 The lights-off trigger needs a re-sync owed and the lights on. Repeat
    1.1 and 1.2 once more (Wi-Fi off; change the OFF time again; save), then
    **before** rejoining the Wi-Fi, wait until at least 10 minutes have passed
    since 3.3's green (the automatic attempts are 10 minutes apart). Then
    rejoin the Wi-Fi with the app open. *Pass:* the row goes green within 30
    seconds (this is a LAN return again). If it instead stays on "hasn't
    reached your lights yet", fewer than 10 minutes had passed — wait the
    remainder, then tap Home → power **off** (the lights-off trigger) and
    check the row goes green within 30 seconds. Either path is a pass if it
    ends green with no Retry; stop if neither does.

## 4. Bounds — one attempt, then held (slice B) — inside 9:00–15:00

4.1 Repeat 1.1 and 1.2 (Wi-Fi off; change the ON time; save). *Pass:* row
    and chip as in 1.2.

4.2 Repeat 1.5 (Wi-Fi back on). *Pass:* green within 30 seconds (attempt 1).

4.3 **Within 10 minutes of 4.2:** repeat 1.1 and 1.2 (Wi-Fi off; change the
    ON time again; save), then Wi-Fi back on with the app open. Wait 60
    seconds. *Pass:* the row **stays** on "Your schedule hasn't reached your
    lights yet. …" with Retry — the second attempt inside ten minutes is
    held. *If it went green:* finding; note both phone times and stop.

4.4 Phone: tap **Retry** once. *Pass:* green within 30 seconds (a manual
    Retry is never held).

4.5 **Browser:** `/json/cfg` → `timers.ins`. *Pass:* the ON row shows the
    time from 4.3.

The six-a-day cap is not tested on the phone (it would take over three
hours of waiting); the suite proves it.

## 5. Queue-not-drop (slice A) — any time of day, on the home Wi-Fi

5.1 Phone: My Schedule, with the bench schedule enabled and green. Toggle it
    **OFF**, then within four seconds toggle it **ON** again. *Pass:* after
    the OFF, the row reads "Saving your latest change. It goes to your
    lights next, automatically." with **no** Retry (the clearing sync is
    verifying); within about 20 seconds it reads "Your schedule is on your
    lights." with no Retry, and the schedule's toggle on the list is **ON**.

5.2 **Browser:** `/json/cfg` → `timers.ins`. *Pass:* the schedule's ON and
    OFF rows are present with `en: 1`, and `/presets.json` still holds its
    slot. (On build 125 the same taps left the unit with no rows and no slot
    while the app showed the schedule ON — that is the bug this proves
    fixed.)

5.3 Phone: three quick toggles — OFF, ON, OFF — within six seconds. Wait
    until the row settles (up to 30 seconds). *Pass:* the row reads "Your
    schedule is on your lights." with no Retry and the list toggle is
    **OFF**.

5.4 **Browser:** `/json/cfg` → `timers.ins`. *Pass:* no `en: 1` row for the
    schedule remains (the unit's last word is the last tap, OFF).

5.5 Phone: toggle the schedule **ON** once and wait for green. *Pass:* green;
    `/json/cfg` shows the rows `en: 1` again.

## 6. The line under the wheels and the 24-hour label (slice C) — any time

6.1 Phone: My Schedule → tap the bench schedule to open the editor. *Pass:*
    under the time wheels a sentence reads like "Lights on at 5:00 PM, off at
    7:00 AM the next morning." with the schedule's own times, and it changes
    as you move the ON wheel.

6.2 Phone: System tab → Edit Profile → set the time format to **24-hour**
    and save. My Schedule → open the bench schedule → set ON to 17:30 and OFF
    to 06:00 → Save. Open it again. *Pass:* the wheels open on 17:30 and
    06:00 (not on the 7:00 PM / 11:00 PM defaults), and the sentence under
    the wheels shows the same times in 24-hour form with "the next morning".
    Then set the profile's time format back to **12-hour** and open the
    schedule once more. *Pass:* the wheels show 5:30 PM and 6:00 AM.

## 7. Restore (phone only)

7.1 Phone: My Schedule → the bench schedule → Delete. Wait for the row.
    *Pass:* the row reads "Your schedule is on your lights." in green.

7.2 **Browser:** `/json/cfg` → `timers.ins`. *Pass:* no row for the bench
    schedule; the rows noted in 0.2 are as they were. `/presets.json`: the
    schedule's slot may still be present — leave it (the app owns slots
    10–41 and reuses them). Do not delete it by hand.

7.3 Phone: Home → power **off** if the lights are on. *Pass:* the spare is
    dark; the chip still reads "Your schedule is on your lights."

## Not covered by this run

- **The failed state** ("Your controller didn't answer…") and **the
  unconfirmed state** ("…one pattern could not be confirmed…"): both need
  the unit to refuse or drop a write, which is not a phone tap or a browser
  read. The suite proves both (`schedule_sync_status_widgets_test.dart`,
  `schedule_sync_option_ii_test.dart`).
- **The status mirror** (the `schedule_sync` field on the account document):
  reading it is a Firestore console read, not a phone tap. The write is
  fire-and-forget and never shown to the customer; the suite proves the
  payload (`schedule_sync_status_test.dart`).
- **The six-a-day cap** (see Part 4).
- **The read-back blind spot** (`fx`/`col` not compared on read-back): slice
  D's job, not in this build.

## Results

| Step | Phone time | Pass / Fail | Seen (row, chip, browser) |
|---|---|---|---|
| 0.1 | | | |
| 0.2 | | | |
| 0.3 | | | |
| 0.4 | | | |
| 0.5 | | | |
| 0.6 | | | |
| 1.1 | | | |
| 1.2 | | | |
| 1.3 | | | |
| 1.4 | | | |
| 1.5 | | | |
| 1.6 | | | |
| 1.7 | | | |
| 1.8 | | | |
| 2.1 | | | |
| 2.2 | | | |
| 2.3 | | | |
| 2.4 | | | |
| 2.5 | | | |
| 3.1 | | | |
| 3.2 | | | |
| 3.3 | | | |
| 3.4 | | | |
| 3.5 | | | |
| 4.1 | | | |
| 4.2 | | | |
| 4.3 | | | |
| 4.4 | | | |
| 4.5 | | | |
| 5.1 | | | |
| 5.2 | | | |
| 5.3 | | | |
| 5.4 | | | |
| 5.5 | | | |
| 6.1 | | | |
| 6.2 | | | |
| 7.1 | | | |
| 7.2 | | | |
| 7.3 | | | |

Not run as of 2026-11-12.
