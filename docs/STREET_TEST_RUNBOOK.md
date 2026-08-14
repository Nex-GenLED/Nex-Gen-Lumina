# Two-home street test — Neighborhood Sync crew fanout

**One page. Read it before the evening, not during.**

The milestone this proves: **a broadcast from one house lights another house,
across networks, with only the initiator's app open.** It has never happened.
Everything to date has been host-only self-apply, a bench stub standing in for
the second home, or a cross-network *join* — all real, none of them this.

---

## Preconditions — verify, do not assume

| # | Check | How | Expected |
|---|---|---|---|
| 1 | Both accounts in the crew | `neighborhoods/OqWsIyvNUwYjel6Dbzwl.memberUids` | `[wrQRUUKy, 5oHhaEaf]` |
| 2 | Fanout armed **for this group** | `config/sync_fanout` | `enabled:true`, `group_allowlist:["OqWsIyvNUwYjel6Dbzwl"]` |
| 3 | Both members `active` | `members/{uid}.participationStatus` | not `paused`/`optedOut` |
| 4 | Both controllers resolvable | `users/{uid}/controllers/*.ip` | Tyler `192.168.1.150`, Ellie `10.0.0.32` |
| 5 | Ellie has a floor | `users/5oHhaEaf….gameday_gate_blocking` | `[]` |
| 6 | Both apps foregrounded, each on **their own LAN** | — | Tyler home Wi-Fi, Ellie hers |

Check 3 is the one that bit twice: rig state moves between sessions (**#72**).
Read it the evening of, not from this page.

**Check 6 is what makes it a street test.** Off-LAN, the bridge relays and the
result is still valid — but the point is two real houses on two real networks.

---

## The run

1. **Snapshot both houses first.** Tyler's rig: `GET /json/state` on `.150`.
   Ellie's: she reports what her lights are doing, in words. Without a before,
   "it changed" is unprovable.
2. **One ad-hoc broadcast from Tyler**, foreground, `fanout:true` — the only
   caller that sets it. Pick a look that is *far from any resting state*:
   a distinctive effect, not just a colour. Palette alone is not enough — a
   `pal:5` broadcast once matched the rig's resting palette and read as a
   partial apply when nothing had been applied at all (#67 run).
3. **Watch both houses.** Expected: both converge on the same look within
   ~5–10 s (bridge round-trip; 30–45 s tail).
4. **Then the leave/end.** Tyler ends the sync. **This is the part with no field
   answer yet** — the restore question. Ellie's floor is now in place, so the
   honest question is: does her house return to her everyday schedule, or sit on
   the sync design? Watch hers specifically; Tyler's rig has a base ladder and
   will flatter the result.

---

## What to capture, whatever happens

- The exact broadcast payload (from Tyler's app or the CF log).
- `users/5oHhaEaf…/commands` — the newest docs, with **`source`**, `status`,
  `controllerIp`, and any `error`.
- Ellie's description of her lights at each step, in her words.
- Timestamps. Convergence latency is a number worth having.

**`source == "sync_fanout"` does NOT prove the crew fanout ran** — the host-only
path uses the same default string. **The discriminator is whose queue the
command is in.** A fanout landed only if there are commands under
`users/5oHhaEaf…/commands`. (Filed as a P3 fix; until then, read the queue.)

---

## Rollback

`config/sync_fanout.enabled = false` — instant, no deploy, both the CF and the
client re-read it live. That is the whole rollback.

If Ellie's house is left on a design she does not want: her floor's next
boundary corrects it, or she loads her base preset from her own app.

---

## Known state going in

- **The allowlist is a staged live wire.** It names Ellie's group. Her house is
  one `fanout:true` away from being commanded — deliberate, and the reason this
  runbook exists. The old scoping's "no customer" safety property is gone by
  choice.
- `initiateSyncSession` is **not** the path under test. It has its own consent
  gate and no session has ever been created in this group.
- Ellie's `base_ladder_asserts_segments` is `true`, so an end-of-event preset
  restore will assert per-segment state on her hardware — the #67 leak
  condition does not apply to her.

## After

Record in `docs/BUILD_LEDGER.md`: which path ran (**by target queue**),
convergence latency both directions, the leave/end result for Ellie's house,
and whether **R-5** moves from amber to green. R-5 is the two-homes crew-fanout
milestone and it stays amber until this test passes — a cross-network join and
a host-only broadcast are not it.
