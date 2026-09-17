---
title: "Nex-Gen Lumina — Homeowner Guide"
subtitle: "How-to, troubleshooting, and FAQ — app 2.5.10+98"
author: "Nex-Gen LED LLC"
date: "September 2026"
pdf_options:
  format: Letter
  margin: 18mm
  printBackground: true
  headerTemplate: '<div style="font-size:8px;width:100%;text-align:center;color:#5C6A88;">Nex-Gen Lumina — Homeowner Guide</div>'
  footerTemplate: '<div style="font-size:8px;width:100%;text-align:center;color:#5C6A88;">Page <span class="pageNumber"></span> of <span class="totalPages"></span></div>'
stylesheet: ["_shared.css"]
body_class: guide
---

<div class="brand">NEX-GEN LUMINA</div>

# Homeowner Guide

<div class="sub">Everything you need to run your permanent outdoor lighting — plus troubleshooting and the questions we hear most.</div>

**Describes Lumina app version 2.5.10+98.**

---

Your lights are installed, tuned, and already talking to the app. This guide covers what you'll use
every evening first, then the deeper features, then the *"why is it doing that?"* moments at the end.

## What you'll need

- An iPhone or Android phone
- The **email and temporary password** your installer gave you
- Your home Wi-Fi password, if you ever move the controller to a new network

---

## 1. Getting the app and signing in

> **Note** — Lumina isn't in the public App Store or Google Play yet, so searching for it won't find
> it. Your installer sends you an **invitation link** instead — TestFlight on iPhone, a Play testing
> link on Android. Accept that invitation first, then come back here.

Sign in with the email and temporary password from your installer. You'll be asked to set your own
password immediately — that's required, not optional, and the old one stops working.

> **Didn't get credentials?** Tap **Forgot Password?** on the sign-in screen and enter your email,
> or contact your installer, who can resend your account details.

### First run

Three short screens:

1. **Welcome** — a greeting by name, and a note that the scheduling assistant can take over your
   week whenever you're ready.
2. **Welcome Home Detection** — asks for location permission. Tap **Allow Location Access** or
   **Skip for Now**; either way the app moves on.
3. **You're all set!** — tap **Go to my lights**.

Then a six-step tour points out the power button, brightness, quick presets, Design Studio, and
lighting areas. You can replay it any time from **System → Feature Tour**.

### Permissions, and what each is for

| Permission | Why | When |
|---|---|---|
| **Location** | Detecting whether you're on your home Wi-Fi, so the app knows to talk to the controller directly or route remotely | First run, and Remote Access setup |
| **Local network** (iPhone) | Finding your controller on your own Wi-Fi | The first time discovery runs |
| **Bluetooth** | Only if you ever set up a controller yourself | Controller setup |

Nothing else is requested, and none of it is required to turn your lights on.

---

## 2. A quick map of the app

Five positions along the bottom dock:

| Position | What lives there |
|---|---|
| **Home** | The house photo, power, brightness, presets, favourites, and the buttons into Design Studio, Game Day and Neighborhood Sync |
| **Schedule** | Your recurring schedules, the weekly view, and Autopilot |
| **Lumina** (centre) | The assistant. Tap for the full screen, press and hold to talk |
| **Explore** | The design library |
| **System** | Settings, remote access, users, profile |

> **Note** — If you've turned on **Simple Mode**, the dock shows only **Home** and **Settings**. The
> Schedule, Lumina and Explore tabs are hidden until you turn it back off.

---

## 3. The Home screen, part by part

### The house photo

A photo of your own house if your installer took one, otherwise a stock image. Change it any time:
**System → My Profile → Edit Profile**.

### The Now Playing bar

Sits over the photo and names whatever is currently on the house — a design name, a pattern name, or
just **Custom** if you've been adjusting things by hand. If the app restarts and the controller is
running something it doesn't recognise, the label clears rather than lie to you.

### Power and brightness

The large button toggles the whole system. The slider below sets brightness for everything at once.
Both act on every controller in your system together.

### Smart Presets

Three one-tap looks that use your roofline map to place accents precisely:

| Preset | What it does |
|---|---|
| **Corner Accents** | Warm white house with a pop of colour on every corner |
| **Peak Highlights** | Highlights every roof peak against a soft base |
| **Feature Outline** | Traces the architecture — accent on every corner, peak and column; runs stay base |

Tap one to choose its **Base** and **Accent** colours, then **Apply**.

> **Warning** — Smart Presets need a roofline map. Without one the section collapses to a single
> card: *"Map your roofline to unlock corner & peak accents."* If your installer mapped your house,
> you'll never see that. If they marked it *map later*, ask them to finish it — several features
> depend on it.

### My Favorites

A grid of four quick-access tiles. The first two are always your chosen whites (see §11). Empty
slots are **+** tiles that take you to Explore.

### The feature buttons

**Design Studio**, **My Designs**, **Game Day** and **Neighborhood Sync**.

---

## 4. Finding a design you love

**Explore** opens the library. Search across everything with the pill at the top — *"Christmas"*,
*"Chiefs"*, *"warm"* — or browse the nine collections:

Architectural Downlighting (White) · Game Day Fan Zone · Holidays · Movies & Superheroes ·
Nature & Outdoors · Parties & Events · Seasonal Vibes · Security & Alerts · My Designs

Open a palette and you land on the tuner: an animated preview of your roofline, the effect, speed
and **Intensity**, and colour-source options (**Any Color**, **My Colors**, **Blended**,
**Auto Colors**). **Apply** puts it on the house.

From a collection you can also **Save to Favorites** or **Save** the look for later.

If a search finds nothing, Lumina offers two ways out: **Chat with Lumina** to describe it, or
**Open Design Studio** to build it.

---

## 5. Design Studio

**Home → Design Studio.** Two modes, chosen with the **AI** / **Manual** switch at the top.

> **Warning** — Both modes need your **roofline setup** complete. Tap **Roofline setup** at the top
> of the screen to check. Without a map, describing a design may appear to do nothing at all.

### AI mode — describe it

Type what you want, or use the microphone. For example:

> *Dark green with red accents on the corners, wave effect moving right to left*

Tap **Create Design**. Lumina interprets it, may ask a clarifying question, and shows the result on
your house photo. Then **Save** (it lands in **My Designs**) or **Apply to Lights**.

**Quick Ideas** chips give you a running start: Warm White, Team Colors, Holiday, Downlighting,
Chase Effect.

### Manual mode — paint it

The full per-pixel editor. Your strip is laid out diode by diode.

| Control | What it does |
|---|---|
| **Channel 1…N** | Pick which run you're painting |
| Tap / drag on the strip | Select one pixel, or drag to select a range |
| **All corners · All peaks · All runs · Anchors** | Select by architecture, using your roofline map |
| **Every-Nth** | Select a repeating pattern — set Start, End and Every |
| **Clear sel.** | Start the selection over |
| **Paint color** | An eleven-swatch palette |
| **Paint** / **Erase** | Apply or remove colour from the selection |
| Undo / redo | Step back and forward |
| **Preview on lights** | Mirror your edits onto the real house as you work |

**Save** names it and files it under My Designs; **Apply to Lights** puts it up immediately.

---

## 6. My Designs

Everything you've created or saved. Reach it from **Home → My Designs** or from Explore. Tap any
design:

| Action | What it does |
|---|---|
| **Apply to Lights** | Put it on the house now |
| **Edit** | Reopen it in the editor |
| **Rename** | Give it a name you'll recognise later |
| **Duplicate** | Copy it, so you can experiment safely |
| **Delete** | Remove it permanently |

> **Note** — If **Edit** is greyed out, that design was composed from a description rather than
> painted in the editor, so there's no editor session to reopen. Use **Duplicate**, or describe what
> you want again in Design Studio.

---

## 7. Talking to Lumina

Tap the centre **Lumina** button for the full screen; press and hold to go straight to listening.

Ask for what you want in ordinary language:

- *Make it warm white*
- *Something spooky for Halloween*
- *Brighter* · *Slower* · *Surprise me*
- *Turn the lights on at seven every night*

Lumina can apply a look, refine what's already running, create a schedule, or start a one-off team
look. Suggestion chips get you started if you're not sure what to say.

> **Note** — Lumina is a fair-use feature. Very heavy use in a single hour is rate-limited with a
> *"please slow down"* message; normal evening use will never reach it.

---

## 8. Schedules

**Schedule tab.** This is what makes the system feel automatic.

### Creating one

Tap **+**, then set:

- **On** and **Off** triggers — a clock **Time**, or **Solar** (**Sunrise** / **Sunset**)
- **Repeat Days**
- **Channels**, if your system has more than one
- **Action** — **Turn Off**, **Run Pattern**, or **Set Brightness**
- The pattern itself, via **Pick**, which opens the full design library including My Designs

### How many you can have — the honest answer

There are two separate limits, and they're different numbers:

| Limit | Value |
|---|---|
| Schedules you can **save** in the app | **20** |
| **Timer slots on your controller** | **8** |

The controller is the one that matters. A clock-based schedule with both an on-time and an off-time
uses **two** slots — so roughly **four** clock schedules fills the controller.

> **Note** — **Sunrise and sunset schedules are free.** They run from their own dedicated slots and
> don't count against the eight. If you're short on room, anchoring to Sunset or Sunrise instead of
> a clock time buys space back.

The editor shows a live meter — *"3 of 8 timer slots used"* — before you save, so you see it coming.
If dated calendar entries are holding slots, it says so: *"(2 held by calendar days)"*. Occasionally
it reads *"checking capacity"*, which simply means it's still reading the controller; the save will
go through.

### Sunrise and sunset

Anchor either trigger to **Solar** and your lights follow the sun at your actual address, adjusting
through the year on their own.

> **Warning** — Solar timing needs your **coordinates set on the controller**, which your installer
> does. If the location was changed recently, the controller doesn't recompute sunrise and sunset
> until it syncs its clock overnight or is restarted. If a brand-new solar schedule doesn't fire the
> first evening, give it one night before calling anyone.

### Scheduling only part of the house

If you have more than one channel, the editor includes a **Channels** picker. Leave it on all
channels for a whole-house schedule, or select individual channels to scope it.

> **Warning** — **Scoping turns the rest off.** While a channel-scoped schedule runs, every channel
> you did *not* select is off for its duration. That's how *"light only the front tonight"* works,
> but it surprises people the first time.

### Sending schedules to the controller

The **Sync** button at the top right pushes your schedules onto the controller itself — which is
what lets them fire with your phone off. It usually happens automatically on save; tap it if the
header shows a stale time.

If a schedule can't be armed, Lumina tells you plainly and offers **Details**.

> **Warning** — Schedules can only be pushed while you're **on your home Wi-Fi**. Away from home,
> edits save to your account and apply the next time you open the app at the house.

### Housekeeping

- Overlapping schedules trigger an orange banner with a **Clean Up** tool. Worth clearing —
  overlaps make lighting unpredictable.
- A schedule's off time wins over anything you applied by hand. When that's coming up, the app warns
  you: *"Heads up — your 'Warm White' schedule turns the lights off at 11:00 PM."*
- Tap any schedule to edit it; **Delete Schedule** is inside the editor.

### The one switch worth knowing about

**System → Turn lights off at sunrise daily.**

Your controller turns the lights off at sunrise every day, whatever is running — even with the app
closed. It's the cheapest insurance against a house that stayed lit all night, and it doesn't
consume one of your eight slots.

---

## 9. Autopilot

**Schedule tab → Autopilot.**

Turn it on and Lumina watches how you actually use the lights, then proposes a week: seasonal
shifts, holidays, and the patterns you keep reaching for.

Two modes:

| Mode | Behaviour |
|---|---|
| **Suggest** | Proposes; nothing is applied until you accept it |
| **Proactive** | Builds the schedule for you straight away |

Suggestions appear in a card at the top of the Schedule tab — accept or dismiss each one.
Everything Autopilot creates is an ordinary schedule you can edit or delete like any other.

---

## 10. Game Day

**Home → Game Day.**

1. Tap **+** and search for your team — NFL, NCAA football and basketball, NBA, MLB, NHL, MLS, NWSL.
2. Tap **Design** to choose the look, or let Lumina build one from the team's colours.
3. Tap **Light Up Now** whenever you want team colours immediately — tailgates, draft night, watch
   parties.

> **Note** — You don't need a schedule for Game Day. Add a team, turn **Autopilot** on for it, and
> it runs on its own.

### The team card, row by row

| Row | What it does |
|---|---|
| **Autopilot** | The master switch for that team. **Everything below it is inactive until this is on.** |
| **Live Scoring** | Whether your lights react to scoring plays |
| **Celebration** | What fires when they do |
| **Skip day games** | Don't bother when the game is fully in daylight at your location |
| **Design variety** | Rotate through team designs, or use the same one every game |
| **Lead time before game** | How early the lights turn over — 30 minutes by default |
| **Refresh Schedule** | Pull the latest game times |

> **Warning** — **"Live Scoring" on its own does nothing.** Score celebrations need *both*
> **Autopilot** and **Live Scoring** on for that team. The two switches look independent; they
> aren't.

> **Note** — **Game Day needs the app open.** Team turnovers and score celebrations run while Lumina
> is open on your phone. The screen can be off, but the app has to be in the foreground. Close it and
> nothing fires.

If you see a banner reading **"Game Day is on — not firing yet"**, tap it. The most common reason is
that the app needs to be opened once at home, on your Wi-Fi, so your controller can report its
channels.

> **Note** — Looking for a **Sports Alerts** screen? There isn't one any more. Everything it used to
> do now lives on the team's card, so a team is set up in one place instead of two. Teams configured
> under the old screen were carried over.

---

## 11. Neighborhood Sync

**Home → Neighborhood Sync.** Several houses, one show.

### Starting or joining a crew

The **+** menu offers **New Crew** and **Join Group**. Starting one asks for a crew name, your home's
name (*"The Smith House"*), and optionally a street and city. You get a six-character invite code to
share. Joining takes a code from a neighbour. A crew holds up to 24 homes.

### Running a show

Pick a style — **Sequential Flow**, **The Pulse**, **The Match**, or **The Complement** — and tap
**Start Neighborhood Sync**. Sequential Flow is the one people mean: one continuous animation that
travels down the street, scaled to each house's diode count so the colour genuinely flows even
between systems of different sizes.

> **Warning** — **Everyone's app has to be open.** A sync reaches a neighbour's house only while that
> neighbour has Lumina open on their phone. It's a "we're all out front together" feature, not an
> unattended one. Agree on a time, everyone opens the app, then start the show.

The owner ends it with **End Group Sync**; members can **Leave Sync** individually.

### Managing a crew

**Leave Group** removes you. If you started the crew you can hand ownership to another member on
your way out.

> **Note** — Creating a sync **schedule** inside a crew saves it and lists it, but scheduled crew
> syncs don't run on their own yet. Start crew shows by hand.

---

## 12. Controlling your lights away from home

**System → System & Device Management → Remote Access.**

At home, the app talks straight to your controller — the fastest path. Away from home, it routes
through your **Lumina Bridge**. The switch between the two is automatic.

1. **Detect Home Network** while you're on your home Wi-Fi, so the app learns which network is home.
2. Leave **Connection Mode** on **ESP32 Bridge** unless your installer set up the webhook path.
3. Turn on **Enable Remote Access**.
4. **Test Bridge** confirms the round trip.

If you don't have a bridge yet, **Set Up Bridge** walks you through it — see the *Lumina Bridge
Setup* guide.

### Knowing which path you're on

The Home screen carries a small badge reading **Direct** or **Via Bridge**, showing how your last
command actually travelled. **Direct** means straight to your controller on your home Wi-Fi;
**Via Bridge** means it was relayed. Tap it to see your recent commands and what the app decided
about your network each time.

It's the fastest way to answer *"why did that feel slow?"* — **Via Bridge** while you're standing in
your own kitchen means the app doesn't recognise your network, and re-running **Detect Home Network**
usually fixes it.

> **Warning** — Away from home you can control the lights, but you **can't push schedule changes**.
> The bridge relays commands, not controller configuration. Schedule edits save to your account and
> apply next time you open the app at the house. Lumina says so when it happens: *"Saved, but your
> controller can only be updated on your home Wi-Fi."*

---

## 13. Sharing access with your household

**System → Manage Users.** Tap **Invite**, enter their email, and send. They get their own sign-in
and their own password. Up to five household members on a residential account.

**Remove Access** revokes it immediately.

---

## 14. Siri

**System → Voice Assistants.**

On iPhone, save the looks you use most (from Explore, via **Save**), then add each one to Siri with
**Add to Siri**. After that, *"Hey Siri, warm white"* works without opening the app.

> **Note** — Amazon Alexa and Google Home integrations are still in development and aren't ready to
> link yet. The screen describes them, but the linking step won't complete. Siri Shortcuts on iPhone
> is the voice path that works today.

Advanced users running Home Assistant will find an integration guide linked on the same screen.

---

## 15. Personal touches

### My Whites

**System → My Profile → Edit Profile → My Whites.**

Choose your **Primary White** and a **Complement White** from five presets — Warm White, Soft White,
Natural White, Cool White, Bright White — or mix your own with R / G / B / W sliders and name it.
Tap a swatch to preview it on the house before committing. Your two whites always occupy the first
two slots of the Favorites grid.

### Simple Mode

**System → Simple Mode.** Reduces the app to **Home** and **Settings** with larger controls. Good
for a guest phone, or for anyone who wants the lights and nothing else. Toggle it back off any time.

### My Properties

**System → My Properties.** Keep a record of multiple properties with names, addresses and which
controllers belong to each.

> **Note** — Today this is a record-keeping list. It does not switch which house the app is
> controlling — the app always talks to the controllers on the network you're on. Multi-property
> switching is coming.

### Refer & Earn

**System → Refer a Friend.** Your personal code, your ambassador status, and the rewards you've
earned. Share it by text.

---

## 16. System settings — what to touch, what to leave alone

### Safe any time

My Profile · My Whites · Simple Mode · Feature Tour · Manage Users · Voice Assistants ·
Remote Access · My Properties · Refer & Earn · Help Center · Turn lights off at sunrise daily

### Leave to your installer

**System & Device Management → Controllers** and the hardware pages behind it. These describe
physical wiring — diode counts, channel assignments, colour order. Changing them will make your
lights behave wrongly, and fixing it is a service call.

**Setup Wizard**, on the same screen, is installer-only and will tell you so.

### Installation Mode

**System & Device Management → Mode** offers **Residential** and **Commercial**. Your installer set
this correctly. Switching to Commercial adds a Zones card; it doesn't unlock anything else, and
switching it without reason only adds confusion.

---

## 17. Troubleshooting

### "We can't find your lights"

A banner on the Home screen with **Retry** and **Set Up Controller**.

1. Are you on your **home Wi-Fi**? Remote control needs a bridge (§12).
2. Is there power to the controller? Check the breaker and any switch feeding it.
3. Tap **Retry**.
4. Power-cycle the controller — off 10 seconds, back on, wait 30.
5. Still nothing: your phone may be on 5 GHz while the controller is on 2.4 GHz. Both work, but if
   your router splits them oddly, contact your installer.

### The lights came on by themselves

Almost always a schedule, Autopilot, or a Game Day team. Check the Schedule tab's weekly view — every
entry is badged with what created it.

### The lights won't stay on

Look for a schedule with an off time coming up, and check whether the daily sunrise-off switch is on.

### A schedule didn't fire

- Did you tap **Sync**? Check the header for a stale time.
- Are you out of timer slots? The editor's meter tells you.
- Is it a brand-new solar schedule? Give it one night (§8).

### Score celebrations aren't happening

Check three things in order: **Autopilot** is on for that team, **Live Scoring** is on, and the app
is open and in the foreground.

### Colours look wrong or washed out

Contact your installer rather than adjusting hardware settings — this is usually a controller
configuration value, and it's a two-minute fix for someone with the right screen.

---

## 18. Frequently asked questions

**Do I have to take these down in the winter?**
No. They're permanent, weatherproof, and designed to stay up.

**Do the lights work if my internet is down?**
Anything already pushed to the controller — schedules, the sunrise-off switch — keeps running. The
app needs the network to send new commands.

**Do they work if my phone is off?**
Schedules and the sunrise-off switch, yes. Game Day, score celebrations and Neighborhood Sync need
the app open.

**Does everyone in a crew need the same system?**
No. Different diode counts and different system sizes all work — each house reports its own count
and the animation is scaled to fit.

**How much power do they use?**
Far less than people expect. At typical evening colour use it's comparable to a couple of household
bulbs; only sustained full-white at full brightness draws meaningfully more.

**Can Nex-Gen see or control my lights?**
Support sees only the diagnostics you choose to send with **Upload system logs**. Your installer can
view your system to help troubleshoot.

**How do I delete my account?**
**System → Security → Delete Account**, under Danger Zone. You'll confirm with your password. This
permanently removes your profile, saved designs, schedules and photos, and cannot be undone. Three
things to know first:

- **Your lights keep running.** Deleting your account doesn't turn anything off or wipe the
  controller. Whatever is already stored on it keeps firing until an installer resets the hardware.
- **A bridge that's still plugged in stays claimed.** The bridge remembers its pairing in its own
  memory. If someone else is taking over the house, it needs a factory reset — that's an installer
  step today; see the *Lumina Bridge Setup* guide.
- **Email us to finish the job.** A little data outside your profile — crew membership, any voice
  links — isn't removed automatically yet. We'll clear it by hand.

---

## 19. Quick reference — where do I find…?

| I want to… | Go to |
|---|---|
| Turn everything on or off | Home → power button |
| Change brightness | Home → slider |
| Accent my corners or peaks | Home → Smart Presets |
| Browse designs | Explore |
| Describe a design | Home → Design Studio → AI |
| Paint pixel by pixel | Home → Design Studio → Manual |
| See what I've saved | Home → My Designs |
| Set a nightly schedule | Schedule → **+** |
| Push schedules to the controller | Schedule → **Sync** |
| Turn the lights off every sunrise | System → Turn lights off at sunrise daily |
| Let Lumina plan the week | Schedule → Autopilot |
| Set up a team | Home → Game Day |
| Score-based light shows | Home → Game Day → team card → Autopilot + Live Scoring |
| Sync with neighbours | Home → Neighborhood Sync |
| Control the lights while away | System → System & Device Management → Remote Access |
| Add a family member | System → Manage Users |
| Set up Siri | System → Voice Assistants |
| Add my house photo | System → My Profile → Edit Profile |
| Choose my white | System → My Whites |
| Simplify the app | System → Simple Mode |
| Replay the tour | System → Feature Tour |
| Delete my account | System → Security → Delete Account |

---

## 20. Your warranty

| Cover | Term |
|---|---|
| **Product** | **5 years** from your install date |
| **Labor** | **1 year minimum** — your dealer may offer longer, so check your paperwork |
| **Expected service life** | **Rated 50,000 hours** — 20+ years at typical evening use |

> **Warning** — **Service life and warranty are two different things.** The 50,000-hour rating is how
> long the diodes are expected to last. It is not a 20-year warranty, and nobody at Nex-Gen or your
> dealership should describe it as one. Your covered terms are the five-year product and
> one-year-minimum labor above.

Warranty claims go through the dealer who installed your system — they're your first call. Have your
install date handy.

---

## 21. Getting help

Start with your installing dealer. They know your house, your wiring, and your configuration, and
most questions are a two-minute answer for them.

For anything they can't resolve, email **support@Nex-GenLED.com**. If you're reporting a problem,
use **System → Help Center → Upload system logs** first and mention that you've done so — it sends
us the diagnostics that make the answer fast.

---

<div class="mantra">BEYOND THE LIGHT.</div>

**Nex-GenLED.com**
