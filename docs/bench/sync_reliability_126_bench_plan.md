# Spare-bench plan — build 126 sync reliability (slice B with slices A and C)

**Written, not run.** Nothing below has contacted a controller. Every step runs
on the owner's go, on the **spare unit only** (the 0.15.4 spare, `.179`). The
home controller `.150` is **excluded by name**: it is the owner's house, it has
the seven bad bytes in its presets file, and nothing here may psave or pdel on
it. No customer unit is touched.

Branch under test: `feat/126-candidate` (slices A, C and B merged; slice D
`feat/126-sync-readback` is **not** in it). Firmware under test: the spare's
0.15.4. The behaviours were measured on 0.15.1 (the home unit's version) and
the app does not branch on version (T-F12); a difference on 0.15.4 is a finding,
not a pass.

What is proven here and nowhere else: the suite proves the app's side with a
fake controller (`test/features/schedule/schedule_resync_owed_test.dart`,
`schedule_sync_queue_test.dart`, `schedule_sync_cross_slice_126_test.dart`).
This plan proves the controller's side: that the owed re-sync actually lands
timers and a preset on the unit, that the queued follow-up's write is the
unit's last word, and that the mirror row appears on the account.

## Before starting

- Bench account (no customer account). Note its uid once, privately, for the
  mirror read in section 3; it never goes into this file or any commit.
- Phone A on the home Wi-Fi with the 126 candidate installed. A way to leave
  the LAN (mobile data) and come back.
- Laptop on the LAN for the controller reads. "Laptop:" marks a read that needs
  it; everything else is seen on the phone.
- The spare's clock resets when it loses power: set it from the laptop after
  any unplug before waiting on a timer.
- The automatic re-sync window is **9:00–15:00 local**. Section 1 must run
  inside it; the "held outside the window" step must run outside it, or the
  phone's clock must be moved. Record the phone's local time at each step.

## 0. Baseline (reads only)

1. Laptop: `GET /json/info` → `ver`, `vid`, `release`. Expect 0.15.4,
   `ESP32_Ethernet`.
2. Laptop: `GET /json/cfg` → save; note `timers.ins` (expect no rows for the
   bench account) and `hw.led.ins` (bus count and lengths).
3. Laptop: `GET /presets.json` → save, sha256. Note which of slots 10–41 are
   occupied.
4. Phone: My Schedule shows no sync status row and Home shows no chip (the
   account has never synced). Expect both absent.

## 1. Owed flag set off-LAN, then the LAN return re-sync (slice B)

Inside 9:00–15:00 local.

1. Phone on mobile data (off the LAN; no bridge configured for the bench
   account, so the app is off-LAN, not relayed). Schedule → `+` → a pattern
   from Explore → ON = now + 20 min, OFF = now + 25 min, every day → Save.
2. Expect on the phone: the status row reads "Your schedule hasn't reached
   your lights yet. It will the next time you open the app on your home Wi-Fi.
   You can retry now if you're home. · just now" with **Retry**; the Home chip
   reads "Your schedule hasn't reached your lights yet." with **Retry**.
3. Laptop: `GET /json/cfg` → `timers.ins` unchanged from baseline (nothing
   was written off-LAN). `GET /presets.json` sha256 unchanged.
4. Kill the app (swipe away). Re-open it still on mobile data. Expect the row
   and chip as in step 2 (the state survived the restart) and no write on the
   laptop reads.
5. Join the home Wi-Fi with the app open. This is the LAN-return trigger.
   Expect within about 15 s: the row flips through nothing alarming and ends
   on "Your schedule is on your lights. · just now" (green) with no Retry;
   the chip reads "Your schedule is on your lights." with no Retry.
6. Laptop: `GET /json/cfg` → `timers.ins` now holds the ON and OFF rows for
   the schedule (hour/minute as set, `en:1`, the ON row's `macro` = the
   schedule's slot). `GET /presets.json` → the slot holds the pattern with
   every bus (T-D4's shape), sha256 changed. Save both.
7. Watch the lights for the 20-minute mark: the ON fires and plays the
   pattern on every channel; at 25 the OFF fires. (Timer fire is the
   controller's; this only confirms the write was real.)
8. Log line to capture from the phone (debug build or device log):
   `SchedulesNotifier: automatic re-sync (lan-return) running — attempt 1 of 6
   today`.

**Held outside the window.** Repeat steps 1–5 with the phone's clock outside
9:00–15:00 (or at 16:30, which was inside the old 8:00–17:00 window). Expect
the row to stay on "hasn't reached your lights yet" after the LAN return, the
laptop reads unchanged, and the log line `automatic re-sync (lan-return) held
— outsideDaytime`. Then tap **Retry** on the row: the sync runs at once at any
hour; expect step 5's end state and step 6's reads.

**Lights ON is not a hold.** With the lights ON (any pattern playing) and a
re-sync owed, repeat the LAN return inside the window. Expect the re-sync to
run (not `held — lightsOn`; that verdict no longer exists), a sub-second change
on the strip that is not visible in daylight from the street, and the lights
back on the pattern they were playing within a second.

**Bounds.** Flap the Wi-Fi off and on twice within ten minutes with a re-sync
owed (make one owed by pulling the controller's Ethernet before a Save, then
restoring it). Expect one run, then `held — tooSoon`. The six-a-day cap is
not bench-tested (it would take three hours); the suite proves it.

## 2. Queue-not-drop (slice A)

1. On the LAN, with the schedule of section 1 enabled and synced, toggle it
   OFF on My Schedule and, within about four seconds, toggle it ON again.
2. Expect on the phone: after the OFF, the row reads "Saving your latest
   change. It goes to your lights next, automatically." (no Retry) while the
   clearing sync verifies; then, within about 15 s, "Your schedule is on your
   lights." with no Retry.
3. Laptop, after the row settles: `GET /json/cfg` → `timers.ins` holds the
   schedule's ON and OFF rows, enabled; `GET /presets.json` holds its slot.
   **Before the fix** (build 125 on the same unit): the controller is left
   with no timers and no slot while the app shows the schedule enabled.
4. Repeat with three quick toggles (OFF, ON, OFF). Expect the last state (OFF)
   on the controller: no enabled timer rows for the schedule, and exactly one
   follow-up write (count the `POST /json/cfg` lines in the app log after the
   first one clears).

## 3. The status mirror (slice B)

1. After section 1 step 5 and section 2 step 2: on the laptop, read the
   bench account's user document (Firebase console, or the Firestore REST
   `documents:get` with the owner's ADC token and the project's
   `x-goog-user-project` header). Expect a map field `schedule_sync` with
   `state: "synced"`, `at` (timestamp of the sync), `mirrored_at` (server
   time), `schedule_count: 1`, `unconverged_preset_ids: []`.
2. After section 1 step 2 (the off-LAN deferral): the same field with
   `state: "deferredOffLan"` (the enum's Dart name; the five values are
   `synced`, `queued`, `deferredOffLan`, `failed`, `writtenNotVerified`).
   `at` is an ISO-8601 UTC string in the phone's copy and a timestamp in the
   mirror. The write is non-fatal: if
   the field is missing, the app must still have shown step 2's row — note
   the miss as a finding, not a failure of the schedule.
3. Expect no other field of the user document to change between the two
   reads (compare the two documents field by field).

## 4. Restore

1. Delete the bench schedule on the phone (on the LAN). Expect the row to
   read "Your schedule is on your lights." and the laptop's `timers.ins` to
   have no rows for it.
2. Laptop: `GET /presets.json` → if the schedule's slot is still present,
   leave it (the app owns slots 10–41 and will reuse it); do not pdel by hand.
3. Compare `GET /json/cfg` to the baseline except `timers.ins`; nothing else
   should differ.

## Results

| Section | Step | Phone time | Expected | Seen | Pass |
|---|---|---|---|---|---|
| | | | | | |

Not run as of 2026-11-12.
