# Build 126 sync read-back bench — the list for Tyler (written, not run)

What this proves: after the app saves a schedule's pattern to a controller, it now reads `/presets.json`
back once (before it restores the live look) and compares the stored slot with what it sent. A slot that
stored differently, or a presets file that could not be read, leaves the schedule ARMED and shows "could
not be confirmed" on My Schedule and on Home, with a Retry, and the app owes itself a bounded automatic
re-sync. Nothing in this slice was run against hardware.

## Units

| Unit | Address | Firmware | Role |
|---|---|---|---|
| Spare | 192.0.2.179 | WLED 0.15.4 | primary bench unit |
| USB unit `e68dbc` | 192.0.2.204 | WLED 16.0.1 | the 16.x read-back shape |
| Home controller | 192.0.2.150 | 0.15.1 | **EXCLUDED** — its presets.json is corrupted; no psave or pdel on it |

(Addresses as the bench rig notes record them; use the rig's current IPs.)

## Rules

- First read `/json/info` on each unit and write down `ver`, `vid`, `arch`.
- Before the first write, snapshot `/json/state`, `/cfg.json` and `/presets.json` from each unit and
  keep the hashes.
- The app does the writing in every step below; the only hand-made write is step 4's deliberate
  corruption of one slot, and it goes to the spare only.
- Stop on the first anomaly instead of retrying.
- Restore at the end (step 9), then check the three hashes.
- Run on a phone that is on the bench Wi-Fi (the sync writes `/json/cfg`, which the bridge cannot
  carry), signed in to a bench account that has only this schedule.

## 1. Baseline: a clean sync reads back as landed

- In the app, create one recurring schedule on the spare: Pattern "Classic Christmas 2" (Explore →
  Holidays), 5:00 PM on, 7:00 AM off, every day. Save.
- Watch My Schedule.
- **Expected:** the status row reads "Your schedule is on your lights. · just now" (green). No Retry.
  Home shows the same chip. `/presets.json` slot 10 carries the schedule's body (fx 84, grp 1, spc 0,
  pal 5, three colour slots, `on:true`, `bri:255`) with `n:"Pattern: Classic Christmas 2"`.
- Also check: `/json/state` is exactly the snapshot look (the restore ran after the read-back).

## 2. Timing of the read-back (log only)

- Open the app's debug log for the sync (`ScheduleSync:` lines).
- **Expected:** after the last `psave` line there is one `/presets.json` read, THEN the live-state
  restore, THEN the 900 ms settle and the cfg write. The gap between the last psave and the restore is
  the read's duration; note it (expect well under a second on a presets file this size).

## 3. What the lights do during the sync (watch the strip)

- With the lights OFF (master off) press Sync in My Schedule.
- **Expected:** the strip lights with the Classic Christmas pattern for a moment (the psave applies its
  body live), then goes dark again (the restore, no fade). Note how long the flash lasts.
- Repeat with the lights ON showing some other look: the strip switches to the pattern for a moment and
  snaps back to the look it had.
- This is the reason the AUTOMATIC re-sync runs only while the lights are off and only 8:00–17:00
  local; a manual Retry runs at once.

## 4. A slot that stored differently reads back as a mismatch (spare only)

- Close the app. With curl, psave a different body into slot 10 on the spare:
  `POST /json/state` with `{"on":true,"bri":255,"seg":[{"id":0,"fx":0,"grp":2,"spc":6,"pal":5,
  "col":[[255,206,166,0],[255,226,202,0],[0,0,0,0]]}],"psave":10,"n":"Pattern: Classic Christmas 2"}`
  (the "4000K, 2 on 6 off" body the home controller was found holding on 2026-11-11).
- Restore the strip's look by hand afterwards (`POST /json/state` with the snapshot's `on`/`bri`/`seg`).
- Re-open the app on the bench Wi-Fi, lights off, between 8:00 and 17:00.
- **Expected:** on launch the app finds nothing owed (the last sync was clean) and does nothing by
  itself. Open the schedule, change nothing but the pattern (pick Classic Christmas 2 again) and Save.
  The sync psaves slot 10 (Option A always writes the pattern slot) and reads it back; on a healthy
  unit it lands, the row reads "on your lights".
- Now make the controller store differently: this cannot be forced from outside on a healthy unit, so
  the mismatch branch is proven by the unit tests (`schedule_sync_pattern_readback_test.dart`); on the
  bench, confirm only that the read-back does not FALSELY report a mismatch on either unit (steps 1 and
  6).

## 5. The owed re-sync after an off-Wi-Fi edit (spare)

- Put the phone on cellular (bridge session). Edit the schedule's off time to 6:00 AM. Save.
- **Expected:** the row reads "Your schedule hasn't reached your lights yet. It will the next time you
  open the app on your home Wi-Fi…" with Retry. Home shows the same headline. Nothing was written to the
  spare (`/presets.json` and the timer table unchanged).
- Kill the app. Rejoin the bench Wi-Fi. Make sure the lights are OFF and it is between 8:00 and 17:00.
  Open the app.
- **Expected:** within a few seconds the sync runs by itself (log: `automatic re-sync (launch) running —
  attempt 1 of 6 today`). The row flips to "on your lights". The timer table carries the 6:00 AM off
  row. The strip flashed the pattern once and went dark.
- Repeat the edit off Wi-Fi, then come back with the lights ON: **expected** the row stays "hasn't
  reached your lights yet", the log says `held — lightsOn`, and pressing Retry runs it at once.
- Come back after 17:00 with the lights off: **expected** `held — outsideDaytime`; Retry runs it.

## 6. The 16.0.1 unit (`e68dbc`, .204)

- Repeat step 1 on the 16.0.1 unit.
- **Expected:** the same green row. Slot 10's stored copy on 16.x may carry extra keys; the compare
  ignores keys the app did not send, so it must still read back as landed. If it reads back as a
  mismatch on a clean save, record the stored body — that is a firmware-shape difference the compare
  must learn, and it is a stop.
- Repeat step 5's first half (off-Wi-Fi edit, then launch at home with the lights off in daytime).

## 7. The bounds (spare)

- Make the spare unreachable (unplug it). On the bench Wi-Fi press Retry.
- **Expected:** the row reads "…the controller didn't answer…" (red) with Retry; a re-sync is owed.
- Plug it back in. Toggle Wi-Fi off and on six times, at least ten minutes apart, lights off, daytime,
  with the spare still unplugged each time.
- **Expected:** each rejoin logs one automatic attempt (`attempt N of 6 today`), the seventh logs
  `held — dailyCapReached`. Two rejoins inside ten minutes log `held — tooSoon` for the second.
- Plug it in and press Retry: **expected** it runs at once (manual is never counted) and the row goes
  green.

## 8. The Firestore mirror

- After any step, open the bench account's `users/{uid}` document in the console.
- **Expected:** field `schedule_sync` with `state`, `at`, `message` (when any), `unconverged_preset_ids`,
  `schedule_count`, `mirrored_at`. No rules change was deployed; the owner's own update rule covers it.
  If the field is absent, the app log says `mirror write dropped — …` and the app behaved normally
  regardless (the mirror is non-fatal by contract).

## 9. Restore

- Delete the bench schedule in the app (the sync purges slot 10 on the next LAN sync).
- Restore `/json/state`, `/cfg.json` and `/presets.json` on both units from the snapshots and compare
  the three hashes.
- Record ver/vid/arch, the flash durations from step 3, and any stop.
