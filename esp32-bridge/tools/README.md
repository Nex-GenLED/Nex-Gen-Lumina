# Bridge firmware 1.3.0 tools

Operator tools for the 1.3.0 rollout: OTA signing and publishing, per-bridge
credentials, and a read-only fleet report. Each tool that writes to Firebase
is a **dry run unless `--confirm`**, touches only what its arguments name,
and never deletes anything.

| Tool | Writes | What for |
|---|---|---|
| `sign_firmware.py` | local files only | Key generation, signing a built image into a manifest, verifying a manifest exactly as the bridge does |
| `publish_firmware.js` | Storage `bridge-firmware/…`, Firestore `bridge_firmware/{channel}` | Offer a signed image to a channel, targeted to explicit deviceIds or `*`; `--disable` is the kill switch |
| `provision_bridge_account.js` | Firebase Auth (one account), optionally one user's `bridge_email` | Create the bridge's own account; hand its credential to the serial tool; move the user's delegation to it (`--flip-user`) or back (`--revert-user`) |
| `provision_bridge_serial.py` | the bridge's NVS, over USB | Deliver the credential; confirm the bridge signs in as itself |
| `fleet_readiness.js` | nothing | Per-bridge table and the rollout gates |

Python tools run with the PlatformIO interpreter (`~/.platformio/penv/Scripts/python.exe`),
which already has `cryptography` and `pyserial`. Node tools use the repo's
`firebase-admin` and Application Default Credentials (or `--key=<service account>`).

## Keys

* Two OTA key pairs: **production** (`src/ota_pubkey.h`, release env) and
  **bench** (`src/ota_pubkey_bench.h`, bench envs). A bench-signed image can
  never install on a fielded bridge.
* Private keys never enter this repository (it is public) —
  `sign_firmware.py keygen` refuses a path inside it. Keep an offline backup of
  the production private key: without it the fleet can only be updated by USB.
* Public key headers may be committed.

## Signing and publishing an update

```bash
pio run -e esp32dev                                   # release image
python tools/sign_firmware.py sign --bin .pio/build/esp32dev/firmware.bin \
    --version 1.3.1 --key <offline>/lumina-ota-prod.pem --out m-1.3.1.json
python tools/sign_firmware.py verify --manifest m-1.3.1.json --pub src/ota_pubkey.h \
    --bin .pio/build/esp32dev/firmware.bin
node tools/publish_firmware.js --manifest=m-1.3.1.json --bin=.pio/build/esp32dev/firmware.bin \
    --channel=beta --devices=<ID> --bucket=<storageBucket>              # dry run
node tools/publish_firmware.js … --confirm
```

`sign` refuses an image whose compiled-in version or board differs from the
arguments, and a bench image (it contains `/api/debug/`) unless `--allow-bench`.
Bridges check the channel every 6 h (+ per-device jitter); `POST
http://<bridge>/api/ota/check` or an `otaCheck` command asks for a check now.

## Giving a bridge its own credential (USB, at the reflash)

```bash
node tools/provision_bridge_account.js --device=<ID>                          # dry run: read registry + plan
node tools/provision_bridge_account.js --device=<ID> --confirm --emit-credential \
  | python tools/provision_bridge_serial.py --port COM<n> --expect-device <ID>
node tools/provision_bridge_account.js --device=<ID> --flip-user --confirm      # within ~2 min
```

The bridge first tries its own account; if its user's queue keeps refusing it
for 2 minutes (the user still delegates to the shared account) it falls back
to the shared account for the rest of that boot and reports
`authMode: legacy_fallback`. Once the user is flipped it converges on its own
account (at the latest after the next progress-watchdog restart). The account
tool refuses to flip a user who has another bridge seen in the last 30 days.

`/api/reset` (moving a bridge between houses) keeps the credential; only an
`erase-flash` removes it — then re-provision with `--reset-password`.

## Phase R3 — end state of the credential migration (NOT applied)

Apply only after `fleet_readiness.js` reports `readyToDisableSharedAccount:
true` and the shared account has been **disabled** (not deleted) in Firebase
Auth for a quiet week:

1. `firestore.rules` — `bridge_registry`: drop `isBridge()` from `allow create`
   and `allow update` (per-bridge accounts keep `isThisBridge()`).
2. `firestore.rules` — anchor `isBridgeForUser` to Admin-created uids, so an
   account that copies a per-bridge email is refused:

   ```
   function isBridgeForUser(userId) {
     return request.auth != null &&
            request.auth.uid.matches('bridge_[0-9A-F]{12}') &&
            exists(/databases/$(database)/documents/users/$(userId)) &&
            get(/databases/$(database)/documents/users/$(userId)).data.bridge_email == request.auth.token.email;
   }
   ```
3. `isBridgeIdentity()` and `storage.rules` `bridge-firmware/`: drop the
   shared-email branch.
4. Build the next image with `-DBRIDGE_LEGACY_SHARED_AUTH=0` (the shared
   credential leaves the binary) and ship it by OTA.
