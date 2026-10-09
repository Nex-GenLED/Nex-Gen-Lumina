# Lumina guides

*Describes build: 2.5.10+116 · Last verified: 2026-10-09*

One source of truth: [`docs/FACTS.md`](../FACTS.md). Every page below states facts from it and lists the ids it used at the bottom. If a page and FACTS disagree, FACTS wins and the page is wrong.

Each page opens with `Describes build:` and `Last verified:`. Nothing unshipped is described as available; it is called "coming" or left out.

## Customer

| Page | Answers |
|---|---|
| [00 Getting started](customer/00-getting-started.md) | I have an invitation. How do I get the app and see my lights? |
| [01 Everyday use](customer/01-everyday-use.md) | Power, brightness, channels, favorites, Explore, the design card |
| [02 Lumina AI](customer/02-lumina-ai.md) | What to say, and which phrases save a schedule |
| [03 Scheduling](customer/03-scheduling.md) | Repeating schedules, one night only, sunrise and sunset, limits |
| [04 Game Day](customer/04-game-day.md) | What it does, how to set it up, what to expect, what not to touch |
| [05 Power outage and recovery](customer/05-power-outage-and-recovery.md) | The lights came back on by themselves and look wrong |
| [06 Troubleshooting](customer/06-troubleshooting.md) | Decision trees: dark, wrong, away from home, Game Day, new phone, voice |
| [07 FAQ](customer/07-faq.md) | Short answers |

## Installer

| Page | Answers |
|---|---|
| [10 Install checklist](installer/10-install-checklist.md) | The day-of list, including firmware (record, never flash) and the setup network |
| [11 Controller setup](installer/11-controller-setup.md) | Outputs, channels, roofline marking, adding an output after install |
| [12 Bridge guide](installer/12-bridge-guide.md) | Pair, test, replace, move, reset, the ten-minute gap |
| [13 Installer SOP](installer/13-installer-sop.md) | Bench prep before an install |

## Dealer

| Page | Answers |
|---|---|
| [20 Dealer guide](dealer/20-dealer-guide.md) | Staff access, the Dealer Dashboard, the pipeline, the deposit gate, payouts, messaging |
| [21 Sales mode](dealer/21-sales-mode.md) | The site visit, the estimate, the signature |

## Internal (Nex-Gen staff)

| Page | Answers |
|---|---|
| [30 Admin operations](internal/30-admin-operations.md) | Tiers, the Corporate Dashboard, PINs, testers, account deletion, support playbooks |
| [31 Release notes](internal/31-release-notes.md) | What each build changed, in customer words, with the tester text |
| [32 Bridge firmware](internal/32-bridge-firmware.md) | What the firmware does, versions, rules, bench flashing |
| [33 Claims policy](internal/33-claims-policy.md) | What may and may not be said to customers and on the website |

## Keeping this true

Run the guard before every build and after every guide edit:

```
node scripts/docs_guard.mjs
```

It fails when a page names a screen label that is not in the app, a path that does not exist, a fact id that is not in FACTS, an unshipped fact described as available, a banned phrase, a credential or address pattern, or a broken link. Build convention 9 in `docs/BUILD_LEDGER.md` makes it part of the ship checklist. Superseded documents live in [`docs/archive/`](../archive/INDEX.md).
