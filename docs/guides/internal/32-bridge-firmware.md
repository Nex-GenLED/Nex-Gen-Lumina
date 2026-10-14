# Bridge firmware

*Describes build: 2.5.10+116 · Bridge firmware 1.2 · Last verified: 2026-10-09 · Internal engineering*

The fielded firmware is `esp32-bridge/src/main.cpp`, version 1.2. There is no other bridge firmware tree; the folder's old README that called this "legacy" and pointed at a replacement directory was wrong.

## What 1.2 does

- Serves six HTTP routes and nothing else: `GET /api/info`, `GET /api/bridge/status`, `POST /api/bridge/pair`, `POST /api/bridge/auth`, `POST /api/reboot`, `POST /api/reset`. Everything else returns a 404 JSON body. No filesystem, no web page.
- First-time Wi-Fi: a captive portal on an access point whose name starts with "Lumina-" plus a device suffix, at 192.168.4.1. The portal closes after five minutes and the bridge restarts. Saved Wi-Fi credentials survive a reset.
- Signs in to the cloud with credentials compiled into the firmware (one shared account for the fleet; the config file is git-ignored and never printed). TLS without certificate validation. Talks to the controller over plain HTTP on the LAN.
- Polls for pending commands every second (config), polls for a pairing request every five seconds, writes a heartbeat and re-asserts its pairing every 30 seconds, and restarts itself after five minutes without successful cloud contact.
- Relays only `GET`/`POST /json/state` and `GET /json/info` to the controller. Never `/json/cfg`: schedules and configuration cannot cross the bridge.
- `POST /api/reset` clears the pairing namespace only, replies ok, and restarts. Wi-Fi settings persist, so the bridge rejoins the same network unpaired. The app's reset call targets this route (fixed 2026-09-17); no UI button calls it.
- Status LED every five seconds: one blink Wi-Fi and cloud up; two Wi-Fi only; three no Wi-Fi; five fast blinks at boot; three when the portal starts.

## The quiet window

Every fielded bridge goes quiet for roughly ten minutes about every seven and a half hours, without rebooting. Several houses show it at staggered times, so it is not one LAN. During the window remote commands fail and the Game Day pre-flight can publish the house as not served for about five minutes. The cause is open. A server-side hold (keep "served" for up to 30 minutes of staleness; widen the staleness threshold to 15 minutes) is built on `fix/gameday-espn-slate` and not deployed.

## Versions and rules

- 1.2 is fielded everywhere. There is no over-the-air update; every firmware change is a bench USB flash.
- 1.3 is built on branch `firmware/bridge-1.3` (watchdog, supervisor, core-0 heartbeat task, signed OTA). Nothing is flashed. Its bench protocol lives outside the repo.
- The Firestore rules were tightened on 2026-10-05 to exactly the operations 1.2 performs. 1.3 writes fields those rules deny: widen the bridge allow-lists in a rules deploy before any 1.3 unit is flashed, and never deploy the whole rules file from the 1.3 branch (it drops release rules).

## Bench flashing (Nex-Gen only)

Only at the bench, only on a unit that is not paired to a live customer. Never in the field.

1. Identify the port by USB vendor and product id, not by remembered COM number; ports move between sessions.
2. Erase, then upload, with PlatformIO from `esp32-bridge/`:
   ```
   pio run --target erase --upload-port COM<n>
   pio run --target upload --upload-port COM<n>
   ```
3. The bridge boots into its Wi-Fi portal. Pairing is then done in the app by the installer (see the [Bridge guide](../installer/12-bridge-guide.md)).

The merged 1.2 image kept outside the repo wipes the settings area when flashed: it is a factory restore, not a state-preserving rollback.

## Do not

- Do not `POST /api/reset` to a live customer bridge to "check" it; it wipes the pairing.
- Do not flash the home bench bridge; use a spare.
- Do not describe a bridge web page anywhere.

*Facts: T-X1, T-X2, T-X3, T-R4, T-R5, T-R7, T-R8, T-O9.*
