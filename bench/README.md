# bench/ — WLED bench verification harness (ledger M-21)

Pure-Dart CLI that automates the schedule/channel verification loops proven out
this week against the bench controller. It **reuses the app's real builders**
(imported, not reinvented) so the harness tests the ACTUAL code:

- `buildCfgPayload` — schedule → `/json/cfg` timers ([cfg_payload_builder.dart](../lib/features/schedule/cfg_payload_builder.dart))
- `timersInsLanded` / `isRealEnabledTimer` — readback comparator ([timer_landing.dart](../lib/features/schedule/timer_landing.dart))
- `buildChannelPowerPayload` — P1-43 per-channel power ([channel_power_payload.dart](../lib/features/wled/channel_power_payload.dart))
- `deviceChannelsFromConfig` — `hw.led.ins` → channels ([device_channel.dart](../lib/features/wled/device_channel.dart))

These were extracted to Flutter-free files (re-exported from their old homes, so
the app is unchanged) so this runs under plain `dart run` with no `dart:ui`.

## Run

```bash
dart run bench/bin/bench.dart <command> [--ip 192.168.1.150]
```

Controller IP resolves from `--ip`, else `bench/config.json`, else the default.
Exit 0 = all checks passed, 1 = any failed (CI- / session-gateable).

| command | what it does |
|---|---|
| `probe` | GET /json/info + /json/cfg; prints ver/vid/uptime/layout; flags layout drift vs `known_layout.json` (P1-42). `probe --update` rewrites the known file after a confirmed physical change. |
| `snapshot` | Captures /json/state + timers + presets.json to `snapshots/snap-<ts>.json`. |
| `cfg-truth` | The en int/bool truth table, automated: `en:1`(int)→stored 1, `en:true`(bool)→stored 0. Permanent regression guard for the polarity saga. |
| `sync-sim` | Builds the REAL cfg via `buildCfgPayload` from a fixture schedule, posts, absorbs any stall (patient poll), readback-asserts via `timersInsLanded`. |
| `preset-verify` | On-device invariants: ON-presets 1/3/4/5 read on, OFF preset 2 reads off, all slots ≤ 250, lease slots (26/28/41) present/untouched. Read-only. |
| `fire-test` | Arms a scratch timer ~3 min ahead (dow Mon=bit0), master off, waits, asserts the strip powered on. |
| `channel-power` | P1-43's four payload shapes via `buildChannelPowerPayload`, asserting emitted payload AND resulting /json/state. |
| `restore` | Re-asserts the timer table from the newest snapshot (exact, slot-aware). |
| `recover` | Repairs a controller left dirty by a run that never restored: from `state/inflight.json` when one exists (timers, gamma, master power), else by scrubbing the harness's own signature rows and re-asserting gamma. The only command that skips pre-flight. |
| `all` | probe → snapshot → cfg-truth → preset-verify → sync-sim → fire-test → channel-power → restore (~8-10 min). **Stops at the first failed restore.** |

Flags: `--ip <addr>` · `--force` (proceed past a pre-flight refusal, loudly).
Exit codes: 0 all checks passed · 1 any failed · **3 pre-flight refused (nothing written)** · 2 usage.

## Restore, pre-flight and the run ledger (2026-09-22)

A harness run on 2026-09-22 left two armed timer slots and a wiped colour
gamma on the live controller, and every later check called it clean. Five
things stacked; each now has a mechanism, not a rule:

| What went wrong | Mechanism now |
|---|---|
| Restore re-posted only the captured rows. WLED merges `timers.ins` **by array index** and a slot only leaves the readback when `macro`, `hour` and `min` are all 0, so a solar-only capture (slot 8) never touched the fixture rows in slots 0/1. | `buildTimerRestoreIns` writes **all 8 general indices**: captured general rows re-packed from 0, `{en:0,hour:0,min:0,macro:0,dow:0}` for the rest. Solar rows (hour 255) are not re-posted — the harness never writes slots 8/9, and a lone re-posted 255 row always lands in slot 8. |
| Every harness cfg POST was timers-only; WLED recomputes the gamma flags from the body on every cfg deserialise, so each write reset `light.gc.col` 2.8→1. | `WledClient.postCfg` routes every body through the app's own `normalizeWledCfgPayload` (`lib/features/wled/wled_cfg_gamma.dart`, Flutter-free). |
| Restore was verified with `timersInsLanded` — a containment check, with a special "cleared schedule" branch for an empty send. Neither says "the table is back". | `timerTableDiff`: **exact**, ordered, row-for-row against the capture, plus `gammaColIntact`. |
| `all` continued past its own failed restore; fire-test then captured the dirty table as its baseline and restored it faithfully. | A failed restore sets the abort flag; `all` stops before its next step and exits 1 with the ledger left inflight. |
| The process was killed mid-wait: `finally` never ran, the summary never printed, the FAIL line existed only in a truncated stdout buffer. | **Pre-flight** on every command except `recover`: reads the timer table + gamma, refuses (exit 3, nothing written) on an inflight ledger, a wiped gamma, or a harness signature row. **Durable ledger** in `bench/state/`: `inflight.json` is written before the first write and removed only after a verified restore; `runs.jsonl` gets every check result and run start/end as they happen. |

`bench/state/` is gitignored but **not transient** — deleting `inflight.json`
by hand silences the guard. Use `recover`.

**Timeouts.** `fire-test` waits ~3 minutes for the timer minute plus 90 s.
**Never run `fire-test` or `all` under a foreground tool or shell timeout
shorter than ~6 minutes.** A timeout kill skips the restore and leaves an
ARMED scratch timer that fires on its own. Run them in the background with
output redirected to a file, then read the file (and `state/runs.jsonl`).

Limitation, by design: general rows come back re-packed from slot 0; the
compacted readback does not expose slot numbers, and the app rewrites all ten
slots on every schedule sync, so the readback — which is what everything reads —
is identical.

## Discipline (enforced as code)

- **Content-Type: application/json on every POST**, with an explicit
  `Content-Length` (WLED's server rejects chunked transfer-encoding — omitting
  this made every POST silently fail on the inaugural run).
- **Capture-before / restore-after** brackets every mutating command — the
  capture is written to `state/inflight.json` BEFORE the first write, the
  restore is slot-aware and verified EXACTLY, and a failed restore aborts.
- Scratch writes touch only a lone scratch timer and (never) preset ids 245-249;
  **NEVER** the lease slots (26/28/41), system presets (1-5), or live schedule
  slots (10-25) without a snapshot first.
- A mid-stall controller is WAITED on (patient poll), never spurious-failed.
- Every check prints `VERIFIED-BY-BENCH: … — <readback evidence>` or
  `FAIL: … — <expected vs actual>`.

## WLED behavior-claim rule

All WLED behavior claims must be tagged `verified-by-bench` / `verified-by-source`
/ `assumption`. This harness is how a claim earns `verified-by-bench`.

Assertion/diff logic is unit-tested in
[test/bench/bench_core_test.dart](../test/bench/bench_core_test.dart) with canned
fixtures; the hardware commands are the integration tests.

## Team LED colour preview (`team_led_preview.dart`)

A separate, interactive tool for tuning [lib/data/team_led_colors.dart](../lib/data/team_led_colors.dart)
by eye. It pushes one team's colours at a time to the **spare** controller and
records keep / adjust verdicts:

```bash
dart run bench/bin/team_led_preview.dart                    # every team, Packers first
dart run bench/bin/team_led_preview.dart --league nfl       # one league (nba, mlb, nhl, mls, nwsl, wnba, ncaa, ncaamb, fifa, cl)
dart run bench/bin/team_led_preview.dart --start nfl_bears  # resume
dart run bench/bin/team_led_preview.dart --smoke            # non-interactive self-check, then restore
```

Keys: `n`/Enter next · `p` prev · `b` both colours (bands) · `1` primary · `2`
secondary · `o` A/B the old brand hex · `k` keep → next · `a` adjust (type a
note) · `s` skip · `q` quit. Verdicts append to `state/team_led_notes.jsonl`.

It does not share this harness's client. Its own client can only `GET` and
`POST /json/state`, and it enforces the rules in code
([bench/src/team_led_preview_core.dart](src/team_led_preview_core.dart), unit-tested in
[test/bench/team_led_preview_core_test.dart](../test/bench/team_led_preview_core_test.dart)):

- **Never `192.168.1.150`.** It is refused by address, by resolved address, and
  by the controller's own reported `ip`. The default target is `192.168.1.173`.
- **Live state only.** No `psave`, `pdel`, `ps`, `pl`, `playlist` or `rb` at
  any depth, and no top-level `ib`, `sb`, `n`, `ql` or `np`. It never writes
  `/json/cfg`, and it reads colour gamma rather than setting it.
- **Restore on exit.** The original `/json/state` is captured before the first
  write, to `state/team_led_preview_capture.json`. It is restored on `q`,
  Ctrl+C or any error, then read back and diffed field by field. If a run is
  killed hard, restore it with `--restore-from bench/state/team_led_preview_capture.json`.

The table assumes the fleet's colour gamma (`light.gc.col` 2.8). The tool
prints the controller's value. Where colour gamma is off, `--emulate-gamma`
applies 2.8 in software so the preview still matches customer houses.
