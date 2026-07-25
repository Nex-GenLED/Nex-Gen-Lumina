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
| `restore` | Re-asserts state from the newest snapshot. |
| `all` | probe → snapshot → cfg-truth → preset-verify → sync-sim → fire-test → channel-power → restore (~8-10 min). |

## Discipline (enforced as code)

- **Content-Type: application/json on every POST**, with an explicit
  `Content-Length` (WLED's server rejects chunked transfer-encoding — omitting
  this made every POST silently fail on the inaugural run).
- **Capture-before / restore-after** brackets every mutating command.
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
