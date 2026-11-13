# Phone bench plan — build 127 table ownership

**Written, not run.** Nothing below has contacted a controller.

| | |
|---|---|
| **Account** | **A test account whose only controller is the spare `.179`.** The owner's home account, whose controller is the `.150`, **must not be used for this run**: an automatic re-sync could psave or pdel the `.150`'s corrupted presets. No customer account, ever. Step 0.3 checks the controller the app is talking to and stops the run if it is not the spare. |
| **Controller** | **The spare only: `.179` on the home LAN, WLED 0.15.4, `ESP32_Ethernet`.** The home unit `.150` is **excluded by name**: nothing in this run may write to it. If at any point the app shows `.150` as the controller it is talking to, the run **stops** (step 0.3). |
| **Build** | This build, installed from TestFlight on the iPhone (2.5.10+127; the TestFlight number is the one the invite named). Branch `feat/127-table-ownership`. |
| **Tools** | The iPhone only, plus a browser on the home Wi-Fi for **read-only** looks at the spare: `http://<spare>/json/info`, `http://<spare>/presets.json`, `http://<spare>/json/cfg`. All three are plain GETs that change nothing on the unit. No laptop scripts, no POSTs, no WLED web UI buttons — with one exception in Part 4, which uses the spare's own web UI to change one timer row, so drift has something to find. |
| **Firmware note** | The behaviours were built against 0.15.1 (the home unit's version) and the app does not branch on version (T-F12). A difference on 0.15.4 is a finding, not a pass. |

What this run proves that the suite cannot: that a real lease write, a real
expiry zeroing and a real toggle write leave a real "Pattern: …" schedule's
rows on a real unit, and that a row changed behind the app's back is seen at
the next launch. The app's side is proven by the suite
(`test/features/schedule/timer_table_ownership_test.dart`,
`timer_table_ownership_rules_test.dart`, `lease_zero_write_verified_test.dart`,
`schedule_sync_keep_rows_test.dart`, `schedule_drift_test.dart`).

## How to read this plan

- Every step is a **phone tap** or a **browser read** of the spare. "Browser:"
  marks a read; everything else is on the phone.
- Every step ends with a **Pass:** line. Write the phone's local time next to
  it in the results table.
- **If a step fails: stop.** Do not tap Retry again, do not repeat the step,
  do not try the next part. Note the phone time, what the row and the chip
  said (word for word), and what the browser reads showed, then stop the run.
  One failed step is a finding to bring back, not something to work around on
  the bench.
- Reading `timers` → `ins` in `/json/cfg`: the unit lists only the rows that
  are not all-zero, so a row's position in the list is not its slot. Compare
  rows by their `hour`, `min`, `macro` and `dow`. `hour` 255 is the sunrise
  slot, 254 the sunset slot.
- Timing: Part 4's automatic re-sync runs only **9:00–15:00 local**. Parts 1
  to 3 can run at any hour.

## 0. Before starting (reads only)

0.1 **Browser:** `/json/info`. *Pass:* `ver` is `0.15.4`, `arch` is `esp32`,
    `ip` ends in `.179`, `name` is the spare's name. Write the name down; it
    must match what the phone shows in 0.3.

0.2 **Browser:** `/json/cfg`. Find `timers` → `ins`. *Pass:* you can see the
    list. Note every row (`hour`, `min`, `macro`, `dow`). Then
    `/presets.json`. *Pass:* it loads; note which numbered slots are present
    (the app uses 10–41).

0.3 Phone: open the app, signed in to the test account, on the home Wi-Fi.
    System tab → the controller entry → details. *Pass:* exactly one
    controller, "IP Address" ends in `.179`, and the name matches 0.1.
    **If it shows `.150`, or more than one controller: STOP. Nothing else in
    this plan may run.**

0.4 Phone: System tab → Remote Access. *Pass:* no bridge is paired.

0.5 Phone: My Schedule. If a schedule from an earlier bench is there, delete
    it (tap it → Delete), wait for the status row to say "Your schedule is on
    your lights.", then **Browser:** `/json/cfg`. *Pass:* no row with a
    `macro` in 10–25 and no row with `macro` 2 at a clock hour.

## 1. A lease promotion over a "Pattern: …" schedule

1.1 Phone: My Schedule → "+" → Repeats weekly → every day, on 5:00 PM, off
    7:00 AM → Explore → pick any catalog pattern (Classic Christmas 2 if it
    is there) → Save. Wait for the row. *Pass:* the row says "Your schedule is
    on your lights."

1.2 **Browser:** `/json/cfg` → `timers.ins`. *Pass:* a row `hour` 17 `min` 0
    `macro` 10 `dow` 127, and a row `hour` 7 `min` 0 `macro` 2 `dow` 127.
    Write both down exactly, including their `start` and `end`.

1.3 Phone: Schedule tab → tomorrow's date → add a one-night look → on 8:30 PM,
    off 9:30 PM → any solid colour → Save. *Pass:* the day shows the night.

1.4 **Browser:** `/json/cfg` → `timers.ins`. *Pass:* the two rows from 1.2 are
    there **unchanged**, and a new row `hour` 20 `min` 30 with a `macro`
    between 26 and 41 and a `dow` with one bit set (tomorrow's day). Nothing
    else changed. On build 126 the two 1.2 rows were gone here.

1.5 Phone: Home. *Pass:* the chip still says "Your schedule is on your
    lights."

## 2. A lease expiry zeroing

2.1 Phone: Schedule tab → tap tomorrow's night from 1.3 → change its off time
    to a time two minutes from now, and its on time to one minute from now →
    Save. (Both inside the lease window; the night will "expire" in two
    minutes.)

2.2 **Browser:** `/json/cfg`. *Pass:* the lease row's `hour`/`min` are the new
    on time; the two 1.2 rows are unchanged.

2.3 Wait seven minutes with the app open on Home (the sweep runs every five
    minutes). **Browser:** `/json/cfg`. *Pass:* the lease row (`macro` 26–41)
    is gone; the two 1.2 rows are there **unchanged**. On build 126 the
    zeroing wrote stubs over them.

2.4 Phone: My Schedule. *Pass:* the schedule from 1.1 is still there, enabled,
    and the row still says "Your schedule is on your lights."

## 3. The sunrise-off toggle

3.1 Phone: System tab → "Turn lights off at sunrise daily" → ON. *Pass:* the
    setting shows on, no error.

3.2 **Browser:** `/json/cfg`. *Pass:* a row `hour` 255 `macro` 2 `dow` 127
    (the sunrise-off), and the two 1.2 rows **unchanged**.

3.3 Phone: the same setting → OFF. *Pass:* the setting shows off, no error.

3.4 **Browser:** `/json/cfg`. *Pass:* the `hour` 255 row now reads `en` 0
    `macro` 0 (the placeholder), and the two 1.2 rows **unchanged**. On build
    126 both toggle writes wiped them.

## 4. Drift detection (inside 9:00–15:00 local)

4.1 Phone: kill the app (swipe it away).

4.2 The one write by hand: in the spare's own web UI (Config → Time &
    Macros → Time controlled presets), change the 17:00 row's minute from 00
    to 05 and save. **Browser:** `/json/cfg`. *Pass:* the row reads `hour` 17
    `min` 5 `macro` 10. Note the time.

4.3 Phone: open the app on the home Wi-Fi, go to Home. Within a minute:
    *Pass:* the chip says "Your schedule isn't on your lights." Then My
    Schedule: *Pass:* the row says "Your schedule isn't on your lights.
    Something changed on your controller. It sends again when you open the
    app at home between 9 am and 3 pm, or tap Retry now." with Retry.

4.4 Wait up to a minute (the automatic re-sync runs at once on launch when it
    is inside the window). *Pass:* the row changes to "Your schedule is on
    your lights."; the chip too. **Browser:** `/json/cfg`. *Pass:* the row is
    back to `hour` 17 `min` 0 `macro` 10 `dow` 127.

4.5 If 4.4 did not change the row within a minute: tap Retry once. *Pass:* as
    4.4. Note that the automatic re-sync did not run (a finding, not a fail of
    this plan: the window, the ten-minute gap and the six-a-day cap are the
    usual reasons; the phone time tells which).

4.6 Phone: kill and reopen the app at home. *Pass:* the row and the chip say
    "Your schedule is on your lights." (a matching read changes nothing).

## 5. Cleanup

5.1 Phone: My Schedule → delete the 1.1 schedule; Schedule tab → delete any
    remaining one-night entries. Wait for "Your schedule is on your lights."

5.2 **Browser:** `/json/cfg`. *Pass:* no row with a `macro` in 10–41 and no
    row with `macro` 2 at a clock hour; the sunrise row is the placeholder.

## Results

| Step | Phone time | Pass / fail | Notes (row and chip text, browser reads) |
|---|---|---|---|
| 0.1 | | | |
| 0.2 | | | |
| 0.3 | | | |
| 0.4 | | | |
| 0.5 | | | |
| 1.1 | | | |
| 1.2 | | | |
| 1.3 | | | |
| 1.4 | | | |
| 1.5 | | | |
| 2.1 | | | |
| 2.2 | | | |
| 2.3 | | | |
| 2.4 | | | |
| 3.1 | | | |
| 3.2 | | | |
| 3.3 | | | |
| 3.4 | | | |
| 4.1 | | | |
| 4.2 | | | |
| 4.3 | | | |
| 4.4 | | | |
| 4.5 | | | |
| 4.6 | | | |
| 5.1 | | | |
| 5.2 | | | |
